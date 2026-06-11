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


# === Parallel Gate (v1.7) — 12-item hard check for parallel_safe phases ===
PHASES_FILE=".phase_control/phases.json"
PARALLEL_GATE_SCRIPT="${SCRIPT_DIR}/parallel_gate_check.py"

PHASE_EXECUTION_MODE=""
if [ -f "$PHASES_FILE" ]; then
    PHASE_EXECUTION_MODE="$(python3 - "$PHASES_FILE" "$PHASE_ID" <<'PY'
import json, sys
phases_file, phase_id = sys.argv[1], sys.argv[2]
try:
    with open(phases_file, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("UNKNOWN")
    sys.exit(0)

for phase in data.get("phases", []):
    pid = phase.get("phase_id") or phase.get("id")
    if pid == phase_id:
        print(phase.get("execution_mode", "sequential"))
        break
else:
    print("UNKNOWN")
PY
)"
fi

if [ "$PHASE_EXECUTION_MODE" = "parallel_safe" ] && [ ! -f "$PARALLEL_GATE_SCRIPT" ]; then
    echo "BLOCKED: parallel_safe phase $PHASE_ID requires parallel_gate_check.py but script is missing" >&2
    exit 1
fi

if [ -f "$PHASES_FILE" ] && [ -f "$PARALLEL_GATE_SCRIPT" ]; then
    PG_STDERR=$(mktemp)
    PARALLEL_GATE_RESULT="$(python3 "$PARALLEL_GATE_SCRIPT" "$PHASES_FILE" "$PHASE_ID" "$LATEST_VERDICT" "$LATEST_ATTEMPT" 2>"$PG_STDERR")"
    PG_EXIT=$?
    PG_STDERR_CONTENT="$(cat "$PG_STDERR" 2>/dev/null)"
    rm -f "$PG_STDERR"

    if [ $PG_EXIT -ne 0 ]; then
        echo "BLOCKED: parallel_gate_check.py crashed for $PHASE_ID (exit $PG_EXIT)" >&2
        if [ -n "$PG_STDERR_CONTENT" ]; then
            echo "$PG_STDERR_CONTENT" >&2
        fi
        exit 1
    fi

    # v1.7: Mark parallel mode for P0-4 check
    if [ -n "$PARALLEL_GATE_RESULT" ] && [[ "$PARALLEL_GATE_RESULT" != "SEQUENTIAL" ]]; then
        export HTE_PARALLEL_GATE=1
    fi

    # If parallel gate returned FAIL, block immediately
    if [ -n "$PARALLEL_GATE_RESULT" ] && [[ "$PARALLEL_GATE_RESULT" == FAIL* ]]; then
        echo "BLOCKED: Parallel gate failed for $PHASE_ID"
        echo "  $PARALLEL_GATE_RESULT" | sed 's/FAIL:/  ❌ /'
        exit 1
    fi
fi

# === v2.0 P0 Checks: Fidelity, Mandate, Coverage (Phase 3-5) ===

GATE_MODE="${HMTE_GATE_MODE:-standard}"
EVIDENCE_FILE=".phase_control/evidence/${PHASE_ID}_attempt_${LATEST_ATTEMPT}.json"
PLAN_FILE="${HMTE_PLAN_FILE:-HTE_v2.0_PROJECT_PLAN.md}"
PLAN_LOCK_FILE="${HMTE_PLAN_LOCK_FILE:-.phase_control/plan_lock.json}"
WORKER_INSTRUCTION=".phase_control/instructions/${PHASE_ID}_worker.json"
VERIFIER_INSTRUCTION=".phase_control/instructions/${PHASE_ID}_verifier.json"

P0_ERRORS=0

# === Phase 3: Plan-to-Delegation Fidelity Check ===
if [[ -f "scripts/hmte-check-fidelity.sh" ]]; then
    echo "🔍 Checking Plan-to-Delegation Fidelity..."
    if [[ -f "$WORKER_INSTRUCTION" ]]; then
        if ! bash scripts/hmte-check-fidelity.sh \
            --instruction "$WORKER_INSTRUCTION" \
            --plan "$PLAN_FILE" \
            --plan-lock "$PLAN_LOCK_FILE" 2>/dev/null; then
            echo "❌ Plan-to-Delegation Fidelity check failed"
            ((P0_ERRORS++))
        else
            echo "✅ Fidelity check passed"
        fi
    else
        echo "⚠️  Worker instruction not found, skipping fidelity check"
    fi
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
    echo "BLOCKED: hmte-check-fidelity.sh not found (required in $GATE_MODE mode)" >&2
    exit 1
else
    echo "SKIP: hmte-check-fidelity.sh not implemented yet (pre-integration mode)"
fi

# === Phase 4: Verifier Mandate Contract Check ===
if [[ -f "scripts/hmte-check-mandate.sh" ]]; then
    echo "🔍 Checking Verifier Mandate Contract..."
    if [[ -f "$VERIFIER_INSTRUCTION" ]]; then
        if ! bash scripts/hmte-check-mandate.sh \
            --instruction "$VERIFIER_INSTRUCTION" \
            --plan "$PLAN_FILE" \
            --plan-lock "$PLAN_LOCK_FILE" 2>/dev/null; then
            echo "❌ Verifier Mandate check failed"
            ((P0_ERRORS++))
        else
            echo "✅ Mandate check passed"
        fi
    else
        echo "⚠️  Verifier instruction not found, skipping mandate check"
    fi
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
    echo "BLOCKED: hmte-check-mandate.sh not found (required in $GATE_MODE mode)" >&2
    exit 1
else
    echo "SKIP: hmte-check-mandate.sh not implemented yet (pre-integration mode)"
fi

# === Phase 5: Plan Coverage Gate Check ===
echo "🔍 Checking Plan Coverage..."
if [[ -f "$EVIDENCE_FILE" && -f "$PLAN_FILE" && -f "$PLAN_LOCK_FILE" ]]; then
    export EVIDENCE_FILE PLAN_LOCK_FILE
    COVERAGE_CHECK=$(python3 <<'COVERAGE_PY'
import json, sys, os

def check_plan_coverage():
    evidence_file = os.environ.get('EVIDENCE_FILE', '')
    plan_lock_file = os.environ.get('PLAN_LOCK_FILE', '')
    
    if not os.path.exists(evidence_file):
        return "FAIL: evidence file not found"
    if not os.path.exists(plan_lock_file):
        return "FAIL: plan lock file not found"
    
    try:
        with open(evidence_file) as f:
            evidence = json.load(f)
        with open(plan_lock_file) as f:
            plan_lock = json.load(f)
    except Exception as e:
        return f"FAIL: cannot parse files: {e}"
    
    issues = []
    
    # Check evidence.plan_ref
    plan_ref = evidence.get('plan_ref', {})
    if not plan_ref:
        issues.append("evidence.plan_ref is missing")
    else:
        evidence_hash = plan_ref.get('plan_hash', '')
        lock_hash = plan_lock.get('plan_hash', '')
        if evidence_hash != lock_hash:
            issues.append(f"plan_hash mismatch: evidence={evidence_hash}, lock={lock_hash}")
        
        plan_item_ids = plan_ref.get('plan_item_ids', [])
        if not plan_item_ids:
            issues.append("evidence.plan_ref.plan_item_ids is empty")
    
    # Check tests_run for required_tests (simplified check)
    tests_run = evidence.get('tests_run', [])
    tests_failed = evidence.get('tests_failed', [])
    tests_skipped = evidence.get('tests_skipped', [])
    tests_timed_out = evidence.get('tests_timed_out', [])
    
    all_tests = set(tests_run + tests_failed + tests_skipped + tests_timed_out)
    
    # Note: Full required_tests check requires parsing plan file
    # For now, just verify tests_run is not empty for non-docs phases
    if not all_tests and not evidence.get('exemption_type'):
        issues.append("no tests executed (tests_run/failed/skipped/timed_out all empty)")
    
    if issues:
        return "FAIL: " + "; ".join(issues)
    return "PASS"

print(check_plan_coverage())
COVERAGE_PY
)
    
    if [[ "$COVERAGE_CHECK" == FAIL* ]]; then
        echo "❌ Plan Coverage check failed: ${COVERAGE_CHECK#FAIL: }"
        ((P0_ERRORS++))
    else
        echo "✅ Plan Coverage check passed"
    fi
else
    echo "⚠️  Evidence/Plan/Lock files not found, skipping coverage check"
fi

# === Pre-integration Hooks for Phase 6-9 ===

# Phase 6: Anomaly Ledger (placeholder)
if [[ -f "scripts/hmte-anomaly-ledger.sh" ]]; then
    echo "🔍 Checking Anomaly Ledger..."
    if ! bash scripts/hmte-anomaly-ledger.sh --evidence "$EVIDENCE_FILE" --plan "$PLAN_FILE" 2>/dev/null; then
        echo "❌ Anomaly Ledger check failed"
        ((P0_ERRORS++))
    else
        echo "✅ Anomaly Ledger check passed"
    fi
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
    echo "BLOCKED: hmte-anomaly-ledger.sh not found (required in $GATE_MODE mode)" >&2
    exit 1
else
    echo "SKIP: hmte-anomaly-ledger.sh not implemented yet (pre-integration mode)"
fi

# Phase 7: Test Disposition (placeholder)
if [[ -f "scripts/hmte-test-disposition.sh" ]]; then
    echo "🔍 Checking Test Disposition..."
    if ! bash scripts/hmte-test-disposition.sh --evidence "$EVIDENCE_FILE" --plan "$PLAN_FILE" 2>/dev/null; then
        echo "❌ Test Disposition check failed"
        ((P0_ERRORS++))
    else
        echo "✅ Test Disposition check passed"
    fi
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
    echo "BLOCKED: hmte-test-disposition.sh not found (required in $GATE_MODE mode)" >&2
    exit 1
else
    echo "SKIP: hmte-test-disposition.sh not implemented yet (pre-integration mode)"
fi

# Phase 8: PASS Contradiction (placeholder)
if [[ -f "scripts/hmte-pass-contradiction.sh" ]]; then
    echo "🔍 Checking PASS Contradiction..."
    ANOMALY_LEDGER=".phase_control/anomaly_ledger.json"
    if ! bash scripts/hmte-pass-contradiction.sh --plan "$PLAN_FILE" --anomaly-ledger "$ANOMALY_LEDGER" 2>/dev/null; then
        echo "❌ PASS Contradiction check failed"
        ((P0_ERRORS++))
    else
        echo "✅ PASS Contradiction check passed"
    fi
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
    echo "BLOCKED: hmte-pass-contradiction.sh not found (required in $GATE_MODE mode)" >&2
    exit 1
else
    echo "SKIP: hmte-pass-contradiction.sh not implemented yet (pre-integration mode)"
fi

# Phase 9: Zero-Finding Justification
if [[ -f "scripts/hmte-check-mandate.sh" ]]; then
    echo "🔍 Checking Zero-Finding Justification..."
    
    # Check if verdict is PASS - zero-finding only applies to PASS verdicts
    VERDICT_STATUS=$(python3 -c "
import json, sys
try:
    with open('$LATEST_VERDICT') as f:
        data = json.load(f)
        # 优先读取 canonical 字段 status，兼容 fallback verdict
        status = data.get('status') or data.get('verdict', 'UNKNOWN')
        print(status)
except:
    print('UNKNOWN')
" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$VERDICT_STATUS" == "PASS" ]]; then
        ANOMALY_LEDGER=".phase_control/anomaly_ledger.json"
        
        # Check if anomaly_count is 0 or near-zero (requires zero-finding justification)
        ANOMALY_COUNT=0
        if [[ -f "$ANOMALY_LEDGER" ]]; then
            ANOMALY_COUNT=$(python3 -c "
import json, sys
try:
    with open('$ANOMALY_LEDGER') as f:
        data = json.load(f)
        # Count only open/unresolved anomalies
        open_count = len([e for e in data.get('entries', []) if e.get('status') == 'open'])
        print(open_count)
except:
    print(0)
" 2>/dev/null || echo 0)
        fi
        
        # If PASS verdict with low anomaly count, require zero-finding justification
        if [[ $ANOMALY_COUNT -le 2 ]]; then
            if ! bash scripts/hmte-check-mandate.sh \
                --verdict "$LATEST_VERDICT" \
                --plan "$PLAN_FILE" \
                --plan-lock "$PLAN_LOCK_FILE" \
                --anomaly-ledger "$ANOMALY_LEDGER" \
                --check-zero-finding 2>/dev/null; then
                echo "❌ Zero-Finding Justification check failed"
                ((P0_ERRORS++))
            else
                echo "✅ Zero-Finding Justification check passed"
            fi
        else
            echo "⚠️  High anomaly count ($ANOMALY_COUNT), zero-finding check skipped"
        fi
    else
        echo "ℹ️  Verdict is $VERDICT_STATUS (not PASS), zero-finding check not applicable"
    fi
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
    echo "BLOCKED: hmte-check-mandate.sh not found (required in $GATE_MODE mode)" >&2
    exit 1
else
    echo "SKIP: zero-finding check not implemented yet (pre-integration mode)"
fi

# Exit if any P0 checks failed
if [[ $P0_ERRORS -gt 0 ]]; then
    echo "BLOCKED: $P0_ERRORS P0 check(s) failed for $PHASE_ID" >&2
    exit 1
fi

case "$verdict" in
  PASS)
    # === P0-4: Verifier Minimum Audit (Enhanced v1.5) ===
    MIN_AUDIT=$(python3 -c "
import json, sys, os, glob

def as_list(value):
    \"\"\"Normalize value to list for type safety\"\"\"
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        return [value] if value else []
    return []

def as_dict(value):
    \"\"\"Normalize value to dict for type safety\"\"\"
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    return {}

def as_bool(value):
    \"\"\"Normalize value to bool for type safety\"\"\"
    return value is True

def check_exemption_conditions(sc, evidence_data):
    \"\"\"Check if phase qualifies for exemption with tightened logic\"\"\"
    exemption_type = sc.get('exemption_type', '')

    # No exemption if not explicitly declared
    if not exemption_type:
        return False, 'no exemption declared'

    # Valid exemption types
    valid_exemptions = ['docs_only', 'config_only', 'planning_only', 'review_only']
    if exemption_type not in valid_exemptions:
        return False, f'invalid exemption_type: {exemption_type}'

    # Get changed files from evidence
    changed_files = as_list(evidence_data.get('changed_files', []))

    # docs_only: ALL changed files must be .md or in docs/
    if exemption_type == 'docs_only':
        if not changed_files:
            return False, 'docs_only requires changed_files'
        for f in changed_files:
            if not (f.endswith('.md') or '/docs/' in f or f.startswith('docs/')):
                return False, f'docs_only but changed non-doc file: {f}'
        return True, 'docs_only exemption valid'

    # config_only: ALL changed files must be config files
    if exemption_type == 'config_only':
        if not changed_files:
            return False, 'config_only requires changed_files'
        config_patterns = ['.json', '.yaml', '.yml', '.toml', '.ini', '.conf', '.config']
        for f in changed_files:
            if not any(f.endswith(p) for p in config_patterns):
                return False, f'config_only but changed non-config file: {f}'
        return True, 'config_only exemption valid'

    # planning_only: NO changed files allowed
    if exemption_type == 'planning_only':
        if changed_files:
            return False, f'planning_only but has changed_files: {changed_files}'
        return True, 'planning_only exemption valid'

    # review_only: only review_only_files, no changed_files
    if exemption_type == 'review_only':
        if changed_files:
            return False, f'review_only but has changed_files: {changed_files}'
        review_files = as_list(evidence_data.get('review_only_files', []))
        if not review_files:
            return False, 'review_only requires review_only_files'
        return True, 'review_only exemption valid'

    return False, 'unknown exemption logic error'

with open(sys.argv[1]) as f:
    v = json.load(f)

sc = as_dict(v.get('adversarial_scorecard', {}))
issues = []

# Load evidence file for exemption checking
evidence_path = '.phase_control/evidence/' + v['phase_id'] + '_attempt_' + str(v['attempt']) + '.json'
evidence_data = {}
try:
    with open(evidence_path) as ef:
        evidence_data = json.load(ef)
except:
    pass

# Check for exemption first
is_exempt, exempt_reason = check_exemption_conditions(sc, evidence_data)

# Note: exemption only relaxes intersection check, not all P0 checks

# === P0 Mandatory Fields (all phases, including exempted) ===

# 1. verification_method (must be enum value)
VALID_METHODS = ['manual_review', 'automated_test', 'cross_check', 'code_review', 'docs_review', 'config_review']
vm = sc.get('verification_method', '')
if not vm or not isinstance(vm, str):
    issues.append('missing verification_method')
elif vm not in VALID_METHODS:
    issues.append(f'verification_method must be one of {VALID_METHODS}, got: {vm}')

# 2. risk_disposition (must be array)
rd = sc.get('risk_disposition', None)
if rd is None:
    issues.append('missing risk_disposition (must be array)')
elif not isinstance(rd, list):
    issues.append('risk_disposition must be array')
else:
    # Check unresolved_risks from evidence
    unresolved_risks = as_list(evidence_data.get('unresolved_risks', []))
    # Filter out 'none', 'None', empty strings
    real_risks = [r for r in unresolved_risks if r and str(r).lower() not in ['none', '']]
    if real_risks and len(rd) < len(real_risks):
        issues.append(f'risk_disposition count ({len(rd)}) < unresolved_risks count ({len(real_risks)})')
    # Validate each disposition entry
    for i, disp in enumerate(rd):
        if not isinstance(disp, dict):
            issues.append(f'risk_disposition[{i}] must be object')
            continue
        if 'risk' not in disp:
            issues.append(f'risk_disposition[{i}] missing risk field')
        if 'disposition' not in disp:
            issues.append(f'risk_disposition[{i}] missing disposition field')
        elif disp['disposition'] not in ['accepted', 'mitigated', 'blocked', 'deferred']:
            issues.append(f'risk_disposition[{i}] disposition must be accepted/mitigated/blocked/deferred')
        if 'reason' not in disp:
            issues.append(f'risk_disposition[{i}] missing reason field')

# 3. re_verification_conclusion (must be >= 20 chars)
rvc = sc.get('re_verification_conclusion', '')
if not rvc or not isinstance(rvc, str):
    issues.append('missing re_verification_conclusion')
elif len(rvc) < 20:
    issues.append(f're_verification_conclusion too short ({len(rvc)} < 20 chars)')

# 4. independently_verified_files (must be non-empty, exist, not .phase_control)
ivf = as_list(sc.get('independently_verified_files', []))
if not ivf:
    issues.append('missing independently_verified_files (must be non-empty list)')
else:
    for f in ivf:
        if not isinstance(f, str) or not f:
            issues.append('independently_verified_files contains invalid entry')
            break
        if f.startswith('.phase_control/'):
            issues.append(f'independently_verified_files cannot point to .phase_control: {f}')
        if not os.path.exists(f):
            issues.append(f'independently_verified_files references non-existent file: {f}')
    # Check intersection with changed_files or artifact_paths (unless exempted)
    if not is_exempt:
        changed_files = as_list(evidence_data.get('changed_files', []))
        artifact_paths = as_list(evidence_data.get('artifact_paths', []))
        work_files = set(changed_files + artifact_paths)
        verified_set = set(ivf)
        if work_files and not (verified_set & work_files):
            issues.append('independently_verified_files has no intersection with changed_files/artifact_paths')

# 5. evidence_paths (must include evidence file and command log)
ep = as_list(sc.get('evidence_paths', []))
if not ep:
    issues.append('missing evidence_paths (must be non-empty list)')
else:
    # v1.7: parallel_safe-aware check
    is_parallel = os.environ.get('HTE_PARALLEL_GATE', '') == '1'
    if is_parallel:
        # For parallel: evidence_paths must contain shard evidence files (from verdict.evidence_paths)
        verdict_ev = set(v.get('evidence_paths', []))
        verdict_cl = set(v.get('command_log_paths', []))
        if not verdict_ev:
            issues.append('parallel: verdict.evidence_paths is empty')
        if not verdict_cl:
            issues.append('parallel: verdict.command_log_paths is empty')
    else:
        has_evidence_file = any(evidence_path in p for p in ep)
        cmd_log_path = evidence_data.get('command_log_path', '')
        has_cmd_log = any(cmd_log_path in p or 'commands.jsonl' in p for p in ep) if cmd_log_path else False
        if not has_evidence_file:
            issues.append('evidence_paths must include evidence file')
        if not has_cmd_log:
            issues.append('evidence_paths must include command log file')

# 6. criteria_passed[].evidence (must not be empty or placeholder)
criteria_passed = as_list(sc.get('criteria_passed', []))
if not criteria_passed:
    issues.append('criteria_passed must be non-empty for PASS verdict')
else:
    PLACEHOLDER_WORDS = ['ok', 'pass', 'done', 'yes', 'good', 'verified', 'checked']
    for i, cp in enumerate(criteria_passed):
        if not isinstance(cp, dict):
            issues.append(f'criteria_passed[{i}] must be an object with criterion and evidence')
            continue
        criterion = cp.get('criterion', '')
        if not criterion or not isinstance(criterion, str):
            issues.append(f'criteria_passed[{i}].criterion is empty')
        evidence = cp.get('evidence', '')
        if not evidence or not isinstance(evidence, str):
            issues.append(f'criteria_passed[{i}].evidence is empty')
        elif evidence.lower().strip() in PLACEHOLDER_WORDS:
            issues.append(f'criteria_passed[{i}].evidence is placeholder: {evidence}')

# 7. PASS verdict must not have criteria_failed
criteria_failed = as_list(sc.get('criteria_failed', []))
if criteria_failed:
    issues.append('PASS verdict cannot have non-empty criteria_failed')

# === Existing P0-4 Fields ===

# 8. command_log_checked (must be true)
if not as_bool(sc.get('command_log_checked')):
    issues.append('missing or false: command_log_checked')

# 9. diff_checked (must be true)
if not as_bool(sc.get('diff_checked')):
    issues.append('missing or false: diff_checked')

# 10. evidence_consistency_checked (must be true)
if not as_bool(sc.get('evidence_consistency_checked')):
    issues.append('missing or false: evidence_consistency_checked')

if issues:
    print('FAIL:' + '; '.join(issues))
else:
    if is_exempt:
        print('PASS:exempted:' + exempt_reason)
    else:
        print('PASS')
" "$LATEST_VERDICT" 2>/dev/null || echo "FAIL:verdict parse error")

    if [[ "$MIN_AUDIT" == FAIL* ]]; then
        echo "BLOCKED: Verifier Minimum Audit failed for $PHASE_ID"
        echo "  $MIN_AUDIT" | sed 's/FAIL:/  ❌ /'
        exit 1
    fi

    # Check if exempted
    if [[ "$MIN_AUDIT" == PASS:exempted:* ]]; then
        EXEMPT_REASON="${MIN_AUDIT#PASS:exempted:}"
        echo "PASS: Phase $PHASE_ID can proceed (audit OK, verdict OK, exempted: $EXEMPT_REASON)"
        exit 0
    fi

    echo "PASS: Phase $PHASE_ID can proceed (audit OK, verdict OK, verifier minimum audit OK)"
    exit 0
    ;;
  FAIL)   echo "BLOCKED: Phase $PHASE_ID verdict=FAIL"; exit 1 ;;
  BLOCK)  echo "BLOCKED: Phase $PHASE_ID verdict=BLOCK"; exit 1 ;;
  *)      echo "BLOCKED: Invalid verdict status: $verdict"; exit 1 ;;
esac
