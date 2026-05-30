#!/bin/bash
set -euo pipefail

# =============================================================================
# hmte-leader-jail.sh — Leader Jail Enforcement (HTE v1.4)
#
# After kickoff, Leader (master-planner) can ONLY write to the control plane.
# This script verifies that no forbidden writes occurred since lock creation.
# v2: Detects UNCOMMITTED changes (working tree + untracked + staged + committed)
#
# Usage: hmte-leader-jail.sh [--mode dev|release]
#   --mode dev     : WARN on violations (default)
#   --mode release : FAIL (exit 1) on violations
# =============================================================================

# --- Color codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Defaults ---
MODE="dev"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            if [[ "$MODE" != "dev" && "$MODE" != "release" ]]; then
                echo -e "${RED}❌ Invalid mode: '$MODE'. Must be 'dev' or 'release'.${NC}" >&2
                exit 1
            fi
            shift 2
            ;;
        *)
            echo -e "${RED}❌ Unknown argument: $1${NC}" >&2
            echo "Usage: hmte-leader-jail.sh [--mode dev|release]" >&2
            exit 1
            ;;
    esac
done

# --- Locate project root (use CWD, not script location) ---
# Leader Jail runs inside the user's project, not inside the hmte repo.
# Fall back to git root if available.
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    PROJECT_ROOT="$(pwd)"
fi
LOCK_FILE="$PROJECT_ROOT/.phase_control/lock.json"

# --- Counters ---
PASS_COUNT=0
VIOLATION_COUNT=0
declare -a VIOLATIONS=()

# --- Helper: log functions ---
log_info()    { echo -e "${BLUE}ℹ  $1${NC}"; }
log_pass()    { echo -e "${GREEN}✅ $1${NC}"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_warn()    { echo -e "${YELLOW}⚠  $1${NC}"; }
log_fail()    { echo -e "${RED}❌ $1${NC}"; VIOLATION_COUNT=$((VIOLATION_COUNT + 1)); }

# =============================================================================
# Step 1: Check if lock.json exists
# =============================================================================
if [[ ! -f "$LOCK_FILE" ]]; then
    if [[ "$MODE" == "release" ]]; then
        log_fail "lock.json not found at $LOCK_FILE"
        log_fail "Leader Jail is REQUIRED in release mode — BLOCKING."
        exit 1
    fi
    log_warn "No lock.json found at $LOCK_FILE"
    log_warn "Leader Jail is not active — nothing to enforce."
    exit 0
fi

log_info "Lock file found: $LOCK_FILE"

# =============================================================================
# Step 2: Parse lock.json for lock_mode and git_head
# =============================================================================
LOCK_JSON="$(cat "$LOCK_FILE")"

LOCK_MODE="$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('lock_mode', ''))
" <<< "$LOCK_JSON" 2>/dev/null || echo "")"

LOCK_GIT_HEAD="$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('git_head', ''))
" <<< "$LOCK_JSON" 2>/dev/null || echo "")"

if [[ -z "$LOCK_MODE" ]]; then
    if [[ "$MODE" == "release" ]]; then
        log_fail "Could not parse lock_mode from lock.json — BLOCKING in release mode."
        exit 1
    fi
    log_warn "Could not parse lock_mode from lock.json"
    exit 0
fi

log_info "Lock mode: $LOCK_MODE"

# =============================================================================
# Step 3: Only enforce if lock_mode is LEADER_JAIL
# =============================================================================
if [[ "$LOCK_MODE" != "LEADER_JAIL" ]]; then
    if [[ "$MODE" == "release" ]]; then
        log_fail "Lock mode is '$LOCK_MODE' (not LEADER_JAIL) — BLOCKING in release mode."
        exit 1
    fi
    log_info "Lock mode is '$LOCK_MODE' (not LEADER_JAIL) — nothing to enforce."
    exit 0
fi

log_info "Leader Jail is ACTIVE. Checking for forbidden writes..."

# =============================================================================
# Step 4: Validate git_head baseline
# =============================================================================
if [[ -z "$LOCK_GIT_HEAD" ]]; then
    if [[ "$MODE" == "release" ]]; then
        log_fail "No git_head in lock.json — BLOCKING in release mode."
        exit 1
    fi
    log_warn "No git_head in lock.json — cannot determine baseline commit."
    log_warn "Skipping Leader Jail enforcement."
    exit 0
fi

log_info "Lock git_head: ${LOCK_GIT_HEAD:0:12}${LOCK_GIT_HEAD:+...}"

# Verify the baseline commit exists
if ! git -C "$PROJECT_ROOT" rev-parse --verify "$LOCK_GIT_HEAD" >/dev/null 2>&1; then
    if [[ "$MODE" == "release" ]]; then
        log_fail "Lock git_head '$LOCK_GIT_HEAD' not found in repository — BLOCKING in release mode."
        exit 1
    fi
    log_warn "Lock git_head '$LOCK_GIT_HEAD' not found in repository."
    log_warn "Skipping Leader Jail enforcement."
    exit 0
fi

CURRENT_HEAD="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "null")"
log_info "Current HEAD: ${CURRENT_HEAD:0:12}..."

# =============================================================================
# Step 5: Get ALL changed files since lock (v2: includes uncommitted!)
# =============================================================================
# Previously only checked baseline..HEAD (committed changes), which missed:
#   - Working tree modifications (Leader edits but doesn't commit)
#   - Staged but uncommitted changes
#   - Untracked new files
#
# Now collects from ALL sources and de-duplicates.

CHANGED_FILES="$(
  {
    # 1. Working tree changes (modified but not staged) vs baseline
    git -C "$PROJECT_ROOT" diff --name-only "$LOCK_GIT_HEAD" -- . 2>/dev/null || true
    # 2. Staged changes vs baseline
    git -C "$PROJECT_ROOT" diff --name-only --cached "$LOCK_GIT_HEAD" -- . 2>/dev/null || true
    # 3. Committed changes (baseline..HEAD) — catches commits between lock and now
    git -C "$PROJECT_ROOT" diff --name-only "$LOCK_GIT_HEAD"..HEAD 2>/dev/null || true
    # 4. Untracked files (not in git at all)
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u
)"

if [[ -z "$CHANGED_FILES" ]]; then
    log_pass "No file changes detected since lock — Leader Jail clean."
    echo ""
    log_info "Summary: $PASS_COUNT checks passed, $VIOLATION_COUNT violations found."
    exit 0
fi

CHANGED_COUNT="$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')"
log_info "Detected $CHANGED_COUNT changed file(s) since lock (working tree + staged + committed + untracked)."

# =============================================================================
# Step 6: Define allowed and forbidden patterns
# =============================================================================

# Allowed write paths (control plane) — everything else goes through
# evidence ownership verification in Step 7b
ALLOWED_PATTERNS=(
    "^\\.phase_control/instructions/"
    "^\\.phase_control/delegations/"
    "^\\.phase_control/state\\.json$"
    "^\\.phase_control/phases\\.json$"
    "^\\.phase_control/goal_lock\\.json$"
    "^\\.phase_control/amendments/"
    "^\\.phase_control/session\\.json$"
    "^\\.phase_control/lock\\.json$"
)

# =============================================================================
# Step 7: Classify changed files (control / placeholder / evidence / project)
# =============================================================================
# Categories:
# - CONTROL: Leader's domain → PASS
# - PLACEHOLDER: .gitkeep → PASS
# - EVIDENCE_PLANE: evidence/verdicts/logs → need matching receipt
# - PROJECT_PLANE: src/ docs/ scripts/ README etc. → defer to Step 7b evidence ownership

declare -a PROJECT_FILES=()    # Files that need evidence ownership verification
declare -a EVIDENCE_FILES=()   # .phase_control/evidence/ files (need worker receipt)
declare -a VERDICT_FILES=()    # .phase_control/verdicts/ files (need verifier receipt)
declare -a LOG_FILES=()        # .phase_control/logs/ files (need runner="hmte exec")

while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # Skip runtime placeholder files created by hmte-kickoff.sh
    case "$file" in
        .phase_control/instructions/.gitkeep|\
        .phase_control/evidence/.gitkeep|\
        .phase_control/verdicts/.gitkeep|\
        .phase_control/logs/.gitkeep|\
        .phase_control/delegations/.gitkeep|\
        .phase_control/errors/.gitkeep|\
        .phase_control/pids/.gitkeep|\
        .phase_control/traces/.gitkeep)
            log_pass "Ignored runtime placeholder: $file"
            continue
            ;;
    esac

    # Check if file is in the control plane (Leader's domain)
    is_control=false
    for pattern in "${ALLOWED_PATTERNS[@]}"; do
        if echo "$file" | grep -qE "$pattern"; then
            is_control=true
            break
        fi
    done

    if $is_control; then
        log_pass "Allowed (control plane): $file"
        continue
    fi

    # Evidence plane files need receipt verification
    if echo "$file" | grep -qE "^\.phase_control/evidence/"; then
        EVIDENCE_FILES+=("$file")
        continue
    fi

    if echo "$file" | grep -qE "^\.phase_control/verdicts/"; then
        VERDICT_FILES+=("$file")
        continue
    fi

    # Log files — checked for runner="hmte exec" in Python
    if echo "$file" | grep -qE "^\.phase_control/logs/"; then
        LOG_FILES+=("$file")
        continue
    fi

    # Everything else is project-plane: needs evidence ownership verification
    PROJECT_FILES+=("$file")
done <<< "$CHANGED_FILES"

# =============================================================================
# Step 7b: Evidence ownership verification (Python-powered)
# =============================================================================
# Verifies that:
#   a) Evidence files have matching worker receipts (role=worker)
#   b) Verdict files have matching verifier receipts (role=verifier)
#   c) Project-plane files are claimed by at least one Worker evidence
#   d) Worker evidence has command log + verdict PASS + phase_gate PASS
#
# Output format: one line per violation, prefixed with "VIOLATION:"
# Empty output = all clean

if [[ ${#PROJECT_FILES[@]} -gt 0 || ${#EVIDENCE_FILES[@]} -gt 0 || ${#VERDICT_FILES[@]} -gt 0 || ${#LOG_FILES[@]} -gt 0 ]]; then
    log_info "Running evidence ownership verification..."

    # Build arrays as JSON for Python
    PROJECT_FILES_JSON=$(printf '%s\n' "${PROJECT_FILES[@]}" | python3 -c "
import json, sys
files = [f.strip() for f in sys.stdin.read().splitlines() if f.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]")

    EVIDENCE_FILES_JSON=$(printf '%s\n' "${EVIDENCE_FILES[@]}" | python3 -c "
import json, sys
files = [f.strip() for f in sys.stdin.read().splitlines() if f.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]")

    VERDICT_FILES_JSON=$(printf '%s\n' "${VERDICT_FILES[@]}" | python3 -c "
import json, sys
files = [f.strip() for f in sys.stdin.read().splitlines() if f.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]")

    LOG_FILES_JSON=$(printf '%s\n' "${LOG_FILES[@]}" | python3 -c "
import json, sys
files = [f.strip() for f in sys.stdin.read().splitlines() if f.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]")

    VERIFICATION_RESULT=$(python3 - "$PROJECT_ROOT" "$PROJECT_FILES_JSON" "$EVIDENCE_FILES_JSON" "$VERDICT_FILES_JSON" "$LOG_FILES_JSON" <<'PY'
import json, os, sys, glob, re

project_root = sys.argv[1]
project_files = json.loads(sys.argv[2])
evidence_files = json.loads(sys.argv[3])
verdict_files = json.loads(sys.argv[4])
log_files = json.loads(sys.argv[5])

violations = []

# --- Helper: parse receipt ---
def parse_receipt(path):
    """Parse a delegation receipt, return (role, phase_id, attempt, expected_output) or None."""
    try:
        with open(os.path.join(project_root, path)) as f:
            r = json.load(f)
        return (
            r.get('role', ''),
            r.get('phase_id', ''),
            r.get('attempt', 0),
            r.get('expected_output_path', '')
        )
    except Exception:
        return None

# --- 1. Evidence files: need matching worker receipt ---
for ev_file in evidence_files:
    # Parse phase_id and attempt from filename: <phase_id>_attempt_<n>.json
    basename = os.path.basename(ev_file)
    m = re.match(r'(.+)_attempt_(\d+)\.json$', basename)
    if not m:
        violations.append(f"VIOLATION: Evidence file name malformed: {ev_file}")
        continue
    phase_id, attempt_str = m.group(1), m.group(2)
    attempt = int(attempt_str)

    receipt_path = f".phase_control/delegations/{phase_id}_attempt_{attempt}_worker.json"
    receipt = parse_receipt(receipt_path)

    if receipt is None:
        violations.append(f"VIOLATION: Evidence without worker receipt: {ev_file} (expected: {receipt_path})")
        continue

    role, rp_phase, rp_attempt, expected_output = receipt
    if role != 'worker':
        violations.append(f"VIOLATION: Evidence receipt role is '{role}' (expected 'worker'): {receipt_path}")
        continue
    if rp_phase != phase_id or rp_attempt != attempt:
        violations.append(f"VIOLATION: Evidence receipt mismatch phase/attempt: {receipt_path}")
        continue

    # Verify verdict exists and PASS
    verdict_path = f".phase_control/verdicts/{phase_id}_attempt_{attempt}.json"
    try:
        with open(os.path.join(project_root, verdict_path)) as f:
            v = json.load(f)
        if v.get('status', '') != 'PASS':
            violations.append(f"VIOLATION: Evidence verdict not PASS: {verdict_path}")
    except Exception:
        violations.append(f"VIOLATION: Evidence missing verdict: {verdict_path}")

    # Verify command log exists
    log_path = f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl"
    if not os.path.exists(os.path.join(project_root, log_path)):
        violations.append(f"VIOLATION: Evidence missing command log: {log_path}")

# --- 2. Verdict files: need matching verifier receipt ---
for vd_file in verdict_files:
    basename = os.path.basename(vd_file)
    m = re.match(r'(.+)_attempt_(\d+)\.json$', basename)
    if not m:
        violations.append(f"VIOLATION: Verdict file name malformed: {vd_file}")
        continue
    phase_id, attempt_str = m.group(1), m.group(2)
    attempt = int(attempt_str)

    receipt_path = f".phase_control/delegations/{phase_id}_attempt_{attempt}_verifier.json"
    receipt = parse_receipt(receipt_path)

    if receipt is None:
        violations.append(f"VIOLATION: Verdict without verifier receipt: {vd_file} (expected: {receipt_path})")
        continue

    role, rp_phase, rp_attempt, _ = receipt
    if role != 'verifier':
        violations.append(f"VIOLATION: Verdict receipt role is '{role}' (expected 'verifier'): {receipt_path}")

# --- 3. Project-plane files: per-file ownership chain (HARDENED v2) ---
# For each project-plane file X, verify the FULL chain:
#   phases.json → evidence → worker receipt → command log (with file reference) →
#   verifier receipt → verdict → phase_gate execution
# Every step is mandatory; any gap → FAIL in release mode.
if project_files:
    # Load phases.json to validate evidence phase_ids
    phases_path = os.path.join(project_root, ".phase_control", "phases.json")
    valid_phase_ids = set()
    try:
        with open(phases_path) as f:
            phases_data = json.load(f)
        for p in phases_data.get('phases', []):
            pid = p.get('phase_id', p.get('id', ''))
            if pid:
                valid_phase_ids.add(pid)
    except Exception:
        pass  # If phases.json is missing/corrupt, all phase_ids fail validation

    # Build evidence index: {file_path: [(evidence_path, phase_id, attempt), ...]}
    evidence_index = {}
    evidence_dir = os.path.join(project_root, ".phase_control", "evidence")
    for ev_path in glob.glob(f"{evidence_dir}/*.json"):
        try:
            with open(ev_path) as f:
                ev = json.load(f)
        except Exception:
            continue
        pid = ev.get('phase_id', '')
        att = ev.get('attempt', 0)
        if not pid or not att:
            continue
        # Skip evidence from phases not in phases.json (anti-fake-phase)
        if valid_phase_ids and pid not in valid_phase_ids:
            continue
        rel_ev = os.path.relpath(ev_path, project_root)
        for cf in ev.get('changed_files', []):
            evidence_index.setdefault(cf, []).append((rel_ev, pid, att))
        for af in ev.get('artifact_paths', []):
            evidence_index.setdefault(af, []).append((rel_ev, pid, att))

    # Readonly command set
    readonly_cmds = {"ls", "cat", "pwd", "echo", "test", "head", "tail", "wc", "grep"}

    for pf in project_files:
        if pf not in evidence_index:
            violations.append(
                f"VIOLATION: Project-plane change without Worker evidence ownership: {pf}"
            )
            continue

        # Find a specific evidence that owns this file with full chain verification
        found_valid_chain = False
        chain_failures = []
        for ev_rel, pid, att in evidence_index.get(pf, []):
            chain_ok = True

            # 3a. Phase must be in phases.json (already filtered above, double-check)
            if valid_phase_ids and pid not in valid_phase_ids:
                chain_failures.append(f"  phase_id '{pid}' not in phases.json")
                chain_ok = False

            # 3b. Worker receipt
            wr_path = f".phase_control/delegations/{pid}_attempt_{att}_worker.json"
            wr = parse_receipt(wr_path)
            if wr is None:
                chain_failures.append(f"  worker receipt missing: {wr_path}")
                chain_ok = False
            else:
                r_role, _, _, expected = wr
                if r_role != 'worker':
                    chain_failures.append(f"  receipt role != worker: {wr_path}")
                    chain_ok = False
                if expected != ev_rel:
                    chain_failures.append(f"  expected_output_path mismatch: receipt={expected} vs evidence={ev_rel}")
                    chain_ok = False

            # 3c. Command log: runner + file reference + readonly check
            cl_path = f".phase_control/logs/{pid}_attempt_{att}.commands.jsonl"
            cl_full = os.path.join(project_root, cl_path)
            pf_basename = pf.rsplit('/', 1)[-1] if '/' in pf else pf
            if not os.path.exists(cl_full):
                chain_failures.append(f"  command log missing: {cl_path}")
                chain_ok = False
            else:
                try:
                    with open(cl_full) as f:
                        lines = [l.strip() for l in f if l.strip()]
                    if not lines:
                        chain_failures.append(f"  command log empty: {cl_path}")
                        chain_ok = False
                    else:
                        file_referenced = False
                        has_write_cmd = False
                        for line in lines:
                            try:
                                entry = json.loads(line)
                            except Exception:
                                chain_failures.append(f"  command log has invalid JSON: {cl_path}")
                                chain_ok = False
                                break
                            runner = entry.get('runner', '')
                            if runner != 'hmte exec':
                                chain_failures.append(f"  command log runner != 'hmte exec': {cl_path} (got '{runner}')")
                                chain_ok = False
                                break
                            cmd = entry.get('command', '')
                            out = entry.get('output_tail', '')
                            # Check file reference (full path or basename)
                            if pf in cmd or pf in out or pf_basename in cmd or pf_basename in out:
                                file_referenced = True
                            # Check for non-readonly commands
                            parts = cmd.strip().split()
                            if parts:
                                base = parts[0].rsplit('/', 1)[-1] if '/' in parts[0] else parts[0]
                                if base not in readonly_cmds:
                                    has_write_cmd = True
                        if chain_ok:
                            if not file_referenced:
                                chain_failures.append(f"  command log does not reference file '{pf}': {cl_path}")
                                chain_ok = False
                            # If evidence claims changed files, must have non-readonly commands
                            if not has_write_cmd and pf in evidence_index:
                                # Check if this specific evidence has non-empty changed_files
                                chain_failures.append(f"  command log has only read-only commands (cat/ls/echo/...): {cl_path}")
                                chain_ok = False
                except Exception:
                    chain_failures.append(f"  command log read error: {cl_path}")
                    chain_ok = False

            # 3d. Verifier receipt
            vr_path = f".phase_control/delegations/{pid}_attempt_{att}_verifier.json"
            vr = parse_receipt(vr_path)
            if vr is None:
                chain_failures.append(f"  verifier receipt missing: {vr_path}")
                chain_ok = False
            else:
                v_role, _, _, vr_expected = vr
                if v_role != 'verifier':
                    chain_failures.append(f"  verifier receipt role != verifier: {vr_path}")
                    chain_ok = False
                vd_expected = f".phase_control/verdicts/{pid}_attempt_{att}.json"
                if vr_expected != vd_expected:
                    chain_failures.append(f"  verifier receipt expected_output_path mismatch: {vr_expected} vs {vd_expected}")
                    chain_ok = False

            # 3e. Verifier verdict
            vd_path = f".phase_control/verdicts/{pid}_attempt_{att}.json"
            vd_full = os.path.join(project_root, vd_path)
            if not os.path.exists(vd_full):
                chain_failures.append(f"  verdict missing: {vd_path}")
                chain_ok = False
            else:
                try:
                    with open(vd_full) as f:
                        vd = json.load(f)
                    if vd.get('status', '') != 'PASS':
                        chain_failures.append(f"  verdict status != PASS: {vd_path}")
                        chain_ok = False
                    sc = vd.get('adversarial_scorecard', {})
                    if not sc:
                        chain_failures.append(f"  verdict missing adversarial_scorecard: {vd_path}")
                        chain_ok = False
                    else:
                        if not sc.get('independently_verified_files'):
                            chain_failures.append(f"  verdict missing independently_verified_files: {vd_path}")
                            chain_ok = False
                        if not sc.get('command_log_checked'):
                            chain_failures.append(f"  verdict command_log_checked != true: {vd_path}")
                            chain_ok = False
                        if not sc.get('diff_checked'):
                            chain_failures.append(f"  verdict diff_checked != true: {vd_path}")
                            chain_ok = False
                        if not sc.get('evidence_consistency_checked'):
                            chain_failures.append(f"  verdict evidence_consistency_checked != true: {vd_path}")
                            chain_ok = False
                except Exception:
                    chain_failures.append(f"  verdict read error: {vd_path}")
                    chain_ok = False

            # 3f. Phase gate execution (MUST actually run)
            pg_script = None
            for cand in [
                os.path.join(project_root, "src", "skills", "hmte", "scripts", "phase_gate.sh"),
                os.path.join(os.environ.get("HMTE_SKILL_DIR", ""), "scripts", "phase_gate.sh"),
                os.path.join(os.environ.get("HMTE_SCRIPT_DIR", ""), "phase_gate.sh"),
                os.path.expanduser("~/.hermes/profiles/default/skills/hmte/scripts/phase_gate.sh"),
                os.path.expanduser("~/.hermes/skills/hmte/scripts/phase_gate.sh"),
            ]:
                if cand and os.path.exists(cand):
                    pg_script = cand
                    break
            # Also search common relative paths
            if not pg_script:
                for cand in [
                    "src/skills/hmte/scripts/phase_gate.sh",
                ]:
                    if os.path.exists(os.path.join(project_root, cand)):
                        pg_script = os.path.join(project_root, cand)
                        break
            if pg_script:
                try:
                    import subprocess as _sp
                    r = _sp.run(
                        ["bash", pg_script, pid, "--attempt", str(att)],
                        capture_output=True, text=True, timeout=30,
                        cwd=project_root
                    )
                    if r.returncode != 0:
                        chain_failures.append(f"  phase_gate FAIL (exit {r.returncode}): {pid} attempt {att}")
                        chain_ok = False
                except Exception as e:
                    chain_failures.append(f"  phase_gate execution error: {e}")
                    chain_ok = False
            else:
                chain_failures.append(f"  phase_gate.sh not found — cannot verify {pid}")
                chain_ok = False

            if chain_ok:
                found_valid_chain = True
                break

        if not found_valid_chain:
            violations.append(
                f"VIOLATION: Project-plane change without valid evidence ownership chain: {pf}"
            )
            for cf in chain_failures:
                violations.append(f"  {cf}")

# --- 4. Log files: runner verification ---
for lf in log_files:
    lf_full = os.path.join(project_root, lf)
    if not os.path.exists(lf_full):
        violations.append(f"VIOLATION: Log file not found: {lf}")
        continue
    try:
        with open(lf_full) as f:
            log_lines = [l.strip() for l in f if l.strip()]
        if not log_lines:
            violations.append(f"VIOLATION: Log file empty: {lf}")
            continue
        for line in log_lines:
            try:
                entry = json.loads(line)
            except Exception:
                violations.append(f"VIOLATION: Log file has invalid JSON: {lf}")
                break
            runner = entry.get('runner', '')
            if runner != 'hmte exec':
                violations.append(f"VIOLATION: Log file runner != 'hmte exec': {lf} (got '{runner}')")
                break
    except Exception:
        violations.append(f"VIOLATION: Log file read error: {lf}")

# --- Output ---
if violations:
    for v in violations:
        print(v)
else:
    print("CLEAN")
PY
    )

    # Process verification results
    if [[ "$VERIFICATION_RESULT" == "CLEAN" ]]; then
        log_pass "Evidence ownership verification: all files properly claimed"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        while IFS= read -r vline; do
            [[ -z "$vline" ]] && continue
            if [[ "$vline" == VIOLATION:* ]]; then
                VIOLATIONS+=("${vline#VIOLATION: }")
                log_fail "${vline#VIOLATION: }"
                VIOLATION_COUNT=$((VIOLATION_COUNT + 1))
            fi
        done <<< "$VERIFICATION_RESULT"
    fi
fi

# =============================================================================
# Step 8: Special check — modified verdict files (not created) after lock
# =============================================================================
VERDICT_FILES="$(git -C "$PROJECT_ROOT" diff --name-only --diff-filter=M "$LOCK_GIT_HEAD" -- ".phase_control/verdicts/" 2>/dev/null || true)"

if [[ -n "$VERDICT_FILES" ]]; then
    while IFS= read -r vfile; do
        [[ -z "$vfile" ]] && continue
        # Check if it's already caught as a violation
        already_reported=false
        for vf in "${VIOLATIONS[@]}"; do
            if [[ "$vf" == "$vfile" ]]; then
                already_reported=true
                break
            fi
        done
        if ! $already_reported; then
            VIOLATIONS+=("$vfile")
            log_fail "VIOLATION — Verdict file MODIFIED (not created): $vfile"
        fi
    done <<< "$VERDICT_FILES"
fi

# =============================================================================
# Step 9: Summary & Exit
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Leader Jail Enforcement Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "  Mode:           $MODE"
log_info "  Lock git_head:  ${LOCK_GIT_HEAD:0:12}"
log_info "  Current HEAD:   ${CURRENT_HEAD:0:12}"
log_info "  Files checked:  $CHANGED_COUNT"
log_info "  Passed:         $PASS_COUNT"

VIOLATION_TOTAL=${#VIOLATIONS[@]}
if [[ "$VIOLATION_TOTAL" -gt 0 ]]; then
    log_fail "  Violations:     $VIOLATION_TOTAL"
    echo ""
    log_fail "Forbidden writes detected:"
    for v in "${VIOLATIONS[@]}"; do
        log_fail "  → $v"
    done
else
    log_pass "  Violations:     0"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$VIOLATION_TOTAL" -gt 0 ]]; then
    if [[ "$MODE" == "release" ]]; then
        log_fail "Leader Jail VIOLATED in release mode — blocking."
        exit 1
    else
        log_warn "Leader Jail VIOLATED in dev mode — warning only."
        exit 0
    fi
else
    log_pass "Leader Jail enforced — no violations."
    exit 0
fi
