#!/usr/bin/env bash
# hmte-verify-claims.sh - TAF P0 Hardening: Evidence Claim Verification
#
# Purpose: Verify that every claimed file in evidence actually exists, is reflected
# in git diff or marked as review_only, and appears in command logs.
#
# Usage: hmte-verify-claims.sh [--mode dev|release] [--phase <phase_id>]

set -euo pipefail

# Cleanup temp files on exit
_CLEANUP_FILES=()
trap 'for f in "${_CLEANUP_FILES[@]:-}"; do rm -f "$f" 2>/dev/null; done' EXIT

# ── Color output ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ${NC} $*"; }
pass_out(){ echo -e "${GREEN}✅${NC} $*"; }
fail_out(){ echo -e "${RED}❌${NC} $*"; }

# ── Banner ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 TAF Evidence Claim Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Defaults ───────────────────────────────────────────────────────────
MODE="dev"
TARGET_PHASE=""
CTRL=".phase_control"

# ── Argument parsing ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            shift
            if [[ $# -eq 0 || "$1" == --* ]]; then
                fail_out "--mode requires a value: dev|release"
                exit 1
            fi
            MODE="$1"
            if [[ "$MODE" != "dev" && "$MODE" != "release" ]]; then
                fail_out "Invalid mode: $MODE (must be dev or release)"
                exit 1
            fi
            shift
            ;;
        --phase)
            shift
            if [[ $# -eq 0 || "$1" == --* ]]; then
                fail_out "--phase requires a value: <phase_id>"
                exit 1
            fi
            TARGET_PHASE="$1"
            shift
            ;;
        -*)
            fail_out "Unknown option: $1"
            echo "Usage: hmte-verify-claims.sh [--mode dev|release] [--phase <phase_id>]"
            exit 1
            ;;
        *)
            fail_out "Unexpected argument: $1"
            echo "Usage: hmte-verify-claims.sh [--mode dev|release] [--phase <phase_id>]"
            exit 1
            ;;
    esac
done

info "Mode: $MODE"
if [[ -n "$TARGET_PHASE" ]]; then
    info "Target phase: $TARGET_PHASE"
else
    info "Target phase: all"
fi
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────
if [[ ! -d "$CTRL" ]]; then
    fail_out ".phase_control directory not found. Run hmte init first."
    exit 1
fi

if [[ ! -f "$CTRL/phases.json" ]]; then
    fail_out "phases.json not found. Leader must create it first."
    exit 1
fi

if [[ ! -f "$CTRL/session.json" ]]; then
    fail_out "session.json not found. Run hmte kickoff first."
    exit 1
fi

# ── Read git baseline ─────────────────────────────────────────────────
BASELINE=$(python3 -c "
import json
s = json.load(open('$CTRL/session.json'))
print(s.get('git_head_at_kickoff', '') or '')
" 2>/dev/null || echo "")

# Get git diff file list (working tree + staged + committed + untracked)
# Aligned with hmte-leader-jail.sh to cover all project changes
if [[ -n "$BASELINE" ]] && git rev-parse --verify "$BASELINE" >/dev/null 2>&1; then
    GIT_DIFF_FILES=$(
        {
            git diff --name-only "$BASELINE" -- . 2>/dev/null || true
            git diff --name-only --cached "$BASELINE" -- . 2>/dev/null || true
            git diff --name-only "$BASELINE"..HEAD 2>/dev/null || true
            git ls-files --others --exclude-standard 2>/dev/null || true
        } | sort -u
    )
else
    if [[ "$MODE" == "release" ]]; then
        fail_out "Git baseline not available in release mode — cannot verify claims against git diff"
        exit 1
    fi
    info "Git baseline not available or not a valid commit; skipping git-diff checks for files"
    GIT_DIFF_FILES=""
fi

# ── Collect phase IDs ─────────────────────────────────────────────────
PHASE_IDS=$(python3 -c "
import json
phases = json.load(open('$CTRL/phases.json'))
for p in phases.get('phases', []):
    print(p['phase_id'])
" 2>/dev/null || echo "")

if [[ -z "$PHASE_IDS" ]]; then
    info "No phases found in phases.json"
    exit 0
fi

# ── Read-only command set ─────────────────────────────────────────────
# Commands that are purely read-only; implementation phases must have at
# least one command NOT in this set.
READONLY_CMDS="ls cat pwd echo test head tail wc grep"

# ── Tracking ───────────────────────────────────────────────────────────
OVERALL_RESULT=0
TOTAL_CHECKS=0
TOTAL_PASS=0
TOTAL_FAIL=0

# ── Helper: determine if phase is implementation type ─────────────────
is_implementation_phase() {
    local pid="$1"
    # Implementation phases: any phase that could produce code/file changes
    # Matches: phase_*, p[0-9]*, impl*, fix*, install*, docs*, release*, deploy*, 
    #          build*, test*, refactor*, update*, migrate*, config*, setup*
    if [[ "$pid" =~ ^(phase_|p[0-9]|impl|fix|install|docs|release|deploy|build|test|refactor|update|migrate|config|setup) ]]; then
        return 0
    fi
    return 1
}

# ── Helper: check if a file path appears in command logs ──────────────
# Returns 0 (true) if found, 1 (false) if not
check_file_in_command_log() {
    local fpath="$1"
    local log_file="$2"

    if [[ ! -f "$log_file" ]]; then
        return 1
    fi

    # Check if file path (or its basename) appears in command or output_tail
    python3 - "$fpath" "$log_file" <<'PY'
import json, sys

fpath = sys.argv[1]
log_file = sys.argv[2]
basename = fpath.rsplit("/", 1)[-1] if "/" in fpath else fpath

found = False
try:
    with open(log_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            cmd = entry.get("command", "")
            out = entry.get("output_tail", "")
            # Check full path or basename in command/output
            if fpath in cmd or fpath in out or basename in cmd or basename in out:
                found = True
                break
except Exception:
    pass

sys.exit(0 if found else 1)
PY
}

# ── Helper: check if command log has non-read-only commands ────────────
# Returns 0 if at least one non-read-only command found, 1 if all read-only
has_non_readonly_commands() {
    local log_file="$1"

    if [[ ! -f "$log_file" ]]; then
        # No log file means we cannot confirm any commands were run
        return 1
    fi

    python3 - "$log_file" <<'PY'
import json, sys

log_file = sys.argv[1]
readonly = {"ls", "cat", "pwd", "echo", "test", "head", "tail", "wc", "grep"}

has_write_cmd = False
try:
    with open(log_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            cmd_str = entry.get("command", "")
            # Extract the base command (first word)
            parts = cmd_str.strip().split()
            if not parts:
                continue
            base_cmd = parts[0]
            # Handle common prefixes like /usr/bin/ls
            if "/" in base_cmd:
                base_cmd = base_cmd.rsplit("/", 1)[-1]
            if base_cmd not in readonly:
                has_write_cmd = True
                break
except Exception:
    pass

sys.exit(0 if has_write_cmd else 1)
PY
}

# ── Process each phase ────────────────────────────────────────────────
while IFS= read -r PHASE_ID; do
    [[ -z "$PHASE_ID" ]] && continue

    # Skip if target phase specified and this isn't it
    if [[ -n "$TARGET_PHASE" && "$TARGET_PHASE" != "$PHASE_ID" ]]; then
        continue
    fi

    info "Processing phase: $PHASE_ID"
    echo ""

    # ── Find latest evidence file(s) ──────────────────────────────────
    # v1.7: Support both sequential and parallel shard evidence
    LATEST_ATTEMPT=0
    LATEST_EVIDENCES=""

    for evf in "$CTRL/evidence/${PHASE_ID}_attempt_"*.json "$CTRL/evidence/${PHASE_ID}"_*_attempt_*.json; do
        [[ ! -f "$evf" ]] && continue
        fname=$(basename "$evf")
        att=$(python3 -c "
import re, sys
m = re.search(r'_attempt_(\\d+)\\.json\$', sys.argv[1])
print(m.group(1) if m else '0')
" "$fname" 2>/dev/null || echo "0")
        if [[ "$att" -gt "$LATEST_ATTEMPT" ]]; then
            LATEST_ATTEMPT="$att"
            LATEST_EVIDENCES="$evf"
        elif [[ "$att" -eq "$LATEST_ATTEMPT" ]] && [[ "$att" -gt 0 ]]; then
            LATEST_EVIDENCES="$LATEST_EVIDENCES|$evf"
        fi
    done

    if [[ -z "$LATEST_EVIDENCES" ]]; then
        info "  No evidence found for phase $PHASE_ID — skipping"
        echo ""
        continue
    fi

    LATEST_EVIDENCE="${LATEST_EVIDENCES%%|*}"
    EV_COUNT=$(echo "$LATEST_EVIDENCES" | tr '|' '\n' | wc -l | tr -d ' ')
    info "  Evidence: $EV_COUNT file(s), attempt $LATEST_ATTEMPT"

    # ── Read changed_files, artifact_paths, review_only_files ──────────
    # v1.7: Aggregate from all evidence files (parallel shard support)
    CLAIMS_JSON=$(python3 -c "
import json, sys
all_c, all_a, all_r = [], [], []
for p in sys.argv[1:]:
    try:
        with open(p) as f: ev = json.load(f)
        all_c.extend(ev.get('changed_files', []))
        all_a.extend(ev.get('artifact_paths', []))
        all_r.extend(ev.get('review_only_files', []))
    except Exception: pass
print(json.dumps({'changed_files':sorted(set(all_c)),'artifact_paths':sorted(set(all_a)),'review_only_files':sorted(set(all_r))}))
" $(echo "$LATEST_EVIDENCES" | tr '|' ' '))

    CHANGED_FILES=$(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1])['changed_files']))" "$CLAIMS_JSON" 2>/dev/null || echo "")
    ARTIFACT_PATHS=$(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1])['artifact_paths']))" "$CLAIMS_JSON" 2>/dev/null || echo "")
    REVIEW_ONLY=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('\n'.join(d.get('review_only_files', [])))" "$CLAIMS_JSON" 2>/dev/null || echo "")

    # Command log file for this phase
    # v1.7: Collect all matching command logs (sequential + shard)
    LOG_FILES=()
    for lf in "$CTRL/logs/${PHASE_ID}_attempt_${LATEST_ATTEMPT}.commands.jsonl" "$CTRL/logs/${PHASE_ID}"_*_attempt_${LATEST_ATTEMPT}.commands.jsonl; do
        [[ -f "$lf" ]] && LOG_FILES+=("$lf")
    done
    if [ ${#LOG_FILES[@]} -gt 1 ]; then
        LOG_FILE=$(mktemp)
        cat "${LOG_FILES[@]}" > "$LOG_FILE"
        _CLEANUP_FILES+=("$LOG_FILE")
    elif [ ${#LOG_FILES[@]} -eq 1 ]; then
        LOG_FILE="${LOG_FILES[0]}"
    else
        LOG_FILE=""
    fi

    # ── Verify each claimed file ───────────────────────────────────────
    # Combine changed_files and artifact_paths into a unified set
    ALL_CLAIMED=""
    if [[ -n "$CHANGED_FILES" ]]; then
        ALL_CLAIMED="$CHANGED_FILES"
    fi
    if [[ -n "$ARTIFACT_PATHS" ]]; then
        if [[ -n "$ALL_CLAIMED" ]]; then
            ALL_CLAIMED="$ALL_CLAIMED"$'\n'"$ARTIFACT_PATHS"
        else
            ALL_CLAIMED="$ARTIFACT_PATHS"
        fi
    fi

    if [[ -z "$ALL_CLAIMED" ]]; then
        info "  No claimed files in evidence — nothing to verify"
        echo ""
        continue
    fi

    while IFS= read -r CLAIMED_FILE; do
        [[ -z "$CLAIMED_FILE" ]] && continue
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        CLAIM_STATUS="PASS"
        CLAIM_REASONS=""

        # Check 1: File must exist on disk
        if [[ ! -f "$CLAIMED_FILE" ]]; then
            CLAIM_STATUS="FAIL"
            CLAIM_REASONS="${CLAIM_REASONS}file_does_not_exist"
        fi

        # Check 2: File must be in git diff OR marked review_only
        IN_GIT_DIFF=false
        if [[ -n "$GIT_DIFF_FILES" ]]; then
            while IFS= read -r gdfile; do
                [[ -z "$gdfile" ]] && continue
                if [[ "$gdfile" == "$CLAIMED_FILE" ]]; then
                    IN_GIT_DIFF=true
                    break
                fi
            done <<< "$GIT_DIFF_FILES"
        fi

        IS_REVIEW_ONLY=false
        if [[ -n "$REVIEW_ONLY" ]]; then
            while IFS= read -r rof; do
                [[ -z "$rof" ]] && continue
                if [[ "$rof" == "$CLAIMED_FILE" ]]; then
                    IS_REVIEW_ONLY=true
                    break
                fi
            done <<< "$REVIEW_ONLY"
        fi

        if [[ "$IN_GIT_DIFF" == false && "$IS_REVIEW_ONLY" == false ]]; then
            if [[ "$MODE" == "release" ]]; then
                # Release mode: strict — must be in git diff or review_only
                CLAIM_STATUS="FAIL"
                CLAIM_REASONS="${CLAIM_REASONS} not_in_git_diff_and_not_review_only"
            else
                # Dev mode: warn but don't fail on this check alone
                CLAIM_REASONS="${CLAIM_REASONS} [WARN:not_in_git_diff]"
            fi
        fi

        # Check 3: File path must appear in command log
        if ! check_file_in_command_log "$CLAIMED_FILE" "$LOG_FILE"; then
            if [[ "$MODE" == "release" ]]; then
                CLAIM_STATUS="FAIL"
                CLAIM_REASONS="${CLAIM_REASONS} not_found_in_command_log"
            else
                CLAIM_REASONS="${CLAIM_REASONS} [WARN:not_in_command_log]"
            fi
        fi

        # Report
        if [[ "$CLAIM_STATUS" == "PASS" ]]; then
            pass_out "  $CLAIMED_FILE — PASS${CLAIM_REASONS}"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            fail_out "  $CLAIMED_FILE — FAIL${CLAIM_REASONS}"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            OVERALL_RESULT=1
        fi
    done <<< "$ALL_CLAIMED"

    # ── Check implementation phase has non-read-only commands ──────────
    if is_implementation_phase "$PHASE_ID"; then
        info "  Phase '$PHASE_ID' is implementation type — checking for write commands"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        if has_non_readonly_commands "$LOG_FILE"; then
            pass_out "  Implementation phase has non-read-only commands — PASS"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            fail_out "  Implementation phase has ONLY read-only commands — FAIL"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            OVERALL_RESULT=1
        fi
    fi

    # ── Release 模式: 如果 changed_files 非空，防止只读命令伪装 ──────────
    if [[ "$MODE" == "release" && -n "$CHANGED_FILES" ]]; then
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        CLAIMED_FILES_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
        # If the phase has CLAIMED to change files, at least one command must be non-read-only
        if has_non_readonly_commands "$LOG_FILE"; then
            pass_out "  Release mode: phase has non-read-only commands for $CLAIMED_FILES_COUNT claimed file(s) — PASS"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            fail_out "  Release mode: phase claims $CLAIMED_FILES_COUNT changed file(s) but command log has ONLY read-only commands (cat/ls/echo/grep...) — FAIL"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            OVERALL_RESULT=1
        fi
    fi

    echo ""
done <<< "$PHASE_IDS"

# ── Summary ────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Summary: $TOTAL_CHECKS checks, $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
    pass_out "All claims verified successfully"
    exit 0
else
    fail_out "$TOTAL_FAIL claim(s) failed verification"
    exit 1
fi
