#!/bin/bash
# Phase gate - check if phase can proceed (audit + verdict)

set -euo pipefail

PHASE_ID="${1:-}"
SPECIFIC_ATTEMPT=""
VERDICTS_DIR=".phase_control/verdicts"
REQUIRE_OBSERVED="${HMTE_REQUIRE_OBSERVED:-false}"

# 参数解析
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --attempt)
            shift
            SPECIFIC_ATTEMPT="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$PHASE_ID" ]; then
    echo "Usage: phase_gate.sh <phase_id> [--attempt N]" >&2
    exit 1
fi

# 自动定位 audit-flow 脚本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/hmte-audit-flow.py" ]; then
    AUDIT_SCRIPT="$SCRIPT_DIR/hmte-audit-flow.py"
elif [ -f "src/skills/hmte/scripts/hmte-audit-flow.py" ]; then
    AUDIT_SCRIPT="src/skills/hmte/scripts/hmte-audit-flow.py"
else
    echo "BLOCKED: hmte-audit-flow.py not found (searched: $SCRIPT_DIR/ and src/skills/hmte/scripts/)" >&2
    exit 1
fi

# phase_id 安全校验
if ! [[ "$PHASE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Invalid phase_id: $PHASE_ID" >&2
    exit 1
fi

# Find latest verdict
LATEST_VERDICT=""
LATEST_ATTEMPT=0

if [ -n "$SPECIFIC_ATTEMPT" ]; then
    # Use specific attempt
    LATEST_ATTEMPT="$SPECIFIC_ATTEMPT"
    LATEST_VERDICT="$VERDICTS_DIR/${PHASE_ID}_attempt_${SPECIFIC_ATTEMPT}.json"
else
    # Find latest verdict
    for verdict_file in "$VERDICTS_DIR/${PHASE_ID}_attempt_"*.json; do
        if [ -f "$verdict_file" ]; then
            ATTEMPT="$(basename "$verdict_file" | sed -n 's/^'"$PHASE_ID"'_attempt_\([0-9][0-9]*\)\.json$/\1/p')"
            if [ -z "$ATTEMPT" ]; then
                continue
            fi
            if [ "$ATTEMPT" -gt "$LATEST_ATTEMPT" ]; then
                LATEST_ATTEMPT=$ATTEMPT
                LATEST_VERDICT="$verdict_file"
            fi
        fi
    done
fi

if [ -z "$LATEST_VERDICT" ]; then
    echo "BLOCKED: No verdict found for $PHASE_ID" >&2
    exit 1
fi

# === Audit flow check ===
echo "🔍 Auditing flow for $PHASE_ID attempt $LATEST_ATTEMPT..."
set +e
AUDIT_RESULT="$(python3 "$AUDIT_SCRIPT" "$PHASE_ID" "$LATEST_ATTEMPT" --json 2>/dev/null)"
AUDIT_EXIT=$?
set -e

if [ -z "$AUDIT_RESULT" ]; then
    AUDIT_RESULT='{"overall":"FAIL","trust_level":"NONE","checks":[{"name":"audit-flow","status":"FAIL","detail":"no output from hmte-audit-flow.py"}]}'
fi

AUDIT_OVERALL="$(echo "$AUDIT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('overall','FAIL'))" 2>/dev/null || echo "FAIL")"
AUDIT_TRUST="$(echo "$AUDIT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('trust_level','NONE'))" 2>/dev/null || echo "NONE")"

if [ "$AUDIT_OVERALL" != "PASS" ] || [ "$AUDIT_EXIT" -ne 0 ]; then
    echo "BLOCKED: Flow audit failed for $PHASE_ID"
    echo "$AUDIT_RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('checks', []):
    icon = '✅' if c['status'] == 'PASS' else '❌'
    detail = f\": {c['detail']}\" if c.get('detail') else ''
    print(f\"  {icon} {c['name']}{detail}\")
" 2>/dev/null || true
    exit 1
fi

# Print trust level warning + enforce OBSERVED if required
if [ "$AUDIT_TRUST" = "INTENT_ONLY" ]; then
    echo "⚠️  Flow audit passed at INTENT_ONLY level, not OBSERVED delegate_task level."
    # 检查关键阶段是否强制要求 OBSERVED
    CRITICAL_PREFIXES="p0 security workflow gate release permission anti_fake"
    for prefix in $CRITICAL_PREFIXES; do
        if [[ "$PHASE_ID" == "$prefix"* ]] && [ "$REQUIRE_OBSERVED" = "true" ]; then
            echo "BLOCKED: Critical phase $PHASE_ID requires OBSERVED delegate_task evidence, got INTENT_ONLY" >&2
            exit 1
        fi
    done
fi

# === Parse verdict ===
verdict="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
    status = data.get('status', 'UNKNOWN')
    if status in ('PASS', 'FAIL', 'BLOCK'):
        print(status)
    else:
        print('INVALID')
" "$LATEST_VERDICT" 2>/dev/null || echo "UNKNOWN")"

case "$verdict" in
  PASS)   echo "PASS: Phase $PHASE_ID can proceed (audit OK, verdict OK)"; exit 0 ;;
  FAIL)   echo "BLOCKED: Phase $PHASE_ID verdict=FAIL"; exit 1 ;;
  BLOCK)  echo "BLOCKED: Phase $PHASE_ID verdict=BLOCK"; exit 1 ;;
  *)      echo "BLOCKED: Invalid verdict status: $verdict"; exit 1 ;;
esac
