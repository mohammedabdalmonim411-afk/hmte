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
        if isinstance(cp, dict):
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
