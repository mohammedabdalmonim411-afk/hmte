#!/bin/bash
# hmte-lint-instructions.sh — HTE v1.4 P0 Instruction Lint
# Scans .phase_control/instructions/*.json for dangerous weakening phrases.
# --mode dev (default): warn only, exit 0
# --mode release:       fail on violations unless explicit_allow_weak_validation + reason
set -euo pipefail

# ─── Color output ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}INFO${NC}  $*"; }
warn()  { echo -e "  ${YELLOW}WARN${NC} $*"; }
fail()  { echo -e "  ${RED}FAIL${NC} $*"; }
pass()  { echo -e "  ${GREEN}PASS${NC} $*"; }

# ─── Parse args ───────────────────────────────────────────────────
MODE="dev"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:?--mode requires a value: dev|release}"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--mode dev|release]" >&2
            exit 1
            ;;
    esac
done

if [[ "$MODE" != "dev" && "$MODE" != "release" ]]; then
    echo "ERROR: --mode must be 'dev' or 'release', got '$MODE'" >&2
    exit 1
fi

echo -e "\n${BLUE}═══ hmte-lint-instructions ─ mode=$MODE ═══${NC}\n"

CTRL=".phase_control"
INSTR_DIR="$CTRL/instructions"

if [ ! -d "$INSTR_DIR" ]; then
    info "No instructions directory found ($INSTR_DIR). Nothing to scan."
    echo -e "\n${GREEN}Summary: 0 scanned, 0 warnings, 0 failures${NC}"
    exit 0
fi

# Collect instruction files into an array (portable, no mapfile)
INSTR_FILES=()
while IFS= read -r f; do
    INSTR_FILES+=("$f")
done < <(find "$INSTR_DIR" -maxdepth 1 -name '*.json' -type f | sort)

if [ ${#INSTR_FILES[@]} -eq 0 ]; then
    info "No instruction files found in $INSTR_DIR"
    echo -e "\n${GREEN}Summary: 0 scanned, 0 warnings, 0 failures${NC}"
    exit 0
fi

# ─── Dangerous weakening phrases ─────────────────────────────────
# Each phrase is a raw string (not regex) — we do case-insensitive matching
WEAKENING_PHRASES=(
    "只检查格式"
    "不需要运行"
    "无需测试"
    "仅代码审查"
    "忽略风险"
    "默认 PASS"
    "不用查看项目文件"
    "不需要独立验证"
    "复用上次 evidence"
)

TOTAL=0
WARN_COUNT=0
FAIL_COUNT=0

# ─── Scan each file ──────────────────────────────────────────────
for f in "${INSTR_FILES[@]}"; do
    TOTAL=$((TOTAL + 1))
    FNAME=$(basename "$f")
    echo -e "${BLUE}───${NC} $FNAME"

    # Build phrase list as JSON array (safest for bash→python3 transfer)
    PHRASES_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:], ensure_ascii=False))" "${WEAKENING_PHRASES[@]}")
    EVAL_RESULT=$(python3 - "$f" "$PHRASES_JSON" <<'PY'
import json, sys
from pathlib import Path

fpath = sys.argv[1]
phrases = json.loads(sys.argv[2])

try:
    text = Path(fpath).read_text(encoding="utf-8")
except Exception as e:
    print(json.dumps({"error": f"READ_ERROR: {e}"}))
    sys.exit(0)

try:
    data = json.loads(text)
except json.JSONDecodeError as e:
    print(json.dumps({"error": f"JSON_ERROR: {e}"}))
    sys.exit(0)

allow_weak = data.get("explicit_allow_weak_validation", False)
reason = data.get("reason", "") or ""

text_lower = text.lower()
matches = []
for phrase in phrases:
    if phrase.lower() in text_lower:
        matches.append(phrase)

print(json.dumps({
    "match_count": len(matches),
    "matches": matches,
    "allowed": bool(allow_weak),
    "reason_len": len(reason)
}, ensure_ascii=False))
PY
)

    # Parse JSON result with single python3 call
    PARSED=$(python3 -c "
import json, sys
data = json.loads('''$EVAL_RESULT''')
print(data.get('match_count', 0))
for m in data.get('matches', []):
    print(m)
print(f\"ALLOWED={1 if data.get('allowed') else 0}\")
print(f\"REASON_LEN={data.get('reason_len', 0)}\")
" 2>/dev/null || echo "0\nALLOWED=0\nREASON_LEN=0")

    # First line is match count
    MATCH_COUNT=$(echo "$PARSED" | head -1)

    # Handle read/json errors
    if echo "$EVAL_RESULT" | grep -q '"error"' 2>/dev/null; then
        ERR_MSG=$(echo "$EVAL_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error',''))" 2>/dev/null)
        fail "$FNAME: $ERR_MSG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if [ "${MATCH_COUNT:-0}" -eq 0 ] 2>/dev/null; then
        pass "$FNAME: no weakening phrases found"
        continue
    fi

    # Extract matched phrases (lines 2..N-2), skip ALLOWED/REASON_LEN lines
    ALLOWED=$(echo "$PARSED" | grep "^ALLOWED=" | cut -d= -f2)
    REASON_LEN=$(echo "$PARSED" | grep "^REASON_LEN=" | cut -d= -f2)

    for phrase in $(echo "$PARSED" | grep -v "^${MATCH_COUNT}$" | grep -v "^ALLOWED=" | grep -v "^REASON_LEN="); do
        [ -z "$phrase" ] && continue
        if [ "$MODE" = "dev" ]; then
            warn "$FNAME: weakening phrase detected → \"$phrase\""
            WARN_COUNT=$((WARN_COUNT + 1))
        elif [ "$MODE" = "release" ]; then
            if [ "$ALLOWED" = "1" ] && [ "$REASON_LEN" -gt 0 ]; then
                warn "$FNAME: weakening phrase → \"$phrase\" (explicitly allowed with reason)"
                WARN_COUNT=$((WARN_COUNT + 1))
            else
                fail "$FNAME: weakening phrase → \"$phrase\" (no explicit_allow_weak_validation + reason)"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        fi
    done
done

# ─── Summary ──────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}═══ Summary ═══${NC}"
echo -e "  Files scanned:  $TOTAL"
echo -e "  Warnings:       ${YELLOW}${WARN_COUNT}${NC}"
echo -e "  Failures:       ${RED}${FAIL_COUNT}${NC}"

if [ "$MODE" = "dev" ]; then
    echo -e "\n${GREEN}Mode: dev — warnings only, exiting 0${NC}"
    exit 0
elif [ "$MODE" = "release" ]; then
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo -e "\n${RED}Mode: release — ${FAIL_COUNT} violation(s) found, exiting 1${NC}"
        exit 1
    else
        echo -e "\n${GREEN}Mode: release — no violations, exiting 0${NC}"
        exit 0
    fi
fi
