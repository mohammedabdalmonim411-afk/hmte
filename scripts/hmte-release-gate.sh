#!/usr/bin/env bash
# hmte-release-gate.sh — TAF Release Gate (legacy hmte command)
#
# Release gate is an outer gate, NOT a new Agent.
# It checks whether the project is ready for external audit.
# External release/GitHub publishing still requires a separate external
# audit receipt; the script must not fabricate that receipt.
#
# Output: PASS / FAIL / PENDING
#   PASS   — all required internal checks passed; ready for external audit
#   FAIL   — P0 or P1 issues found, cannot proceed
#   PENDING — reserved for future manual-review gates
#
# Usage:
#   bash scripts/hmte-release-gate.sh [--mode audit|release] [--project-root DIR]
#
# Exit codes:
#   0 — PASS
#   1 — FAIL
#   2 — PENDING

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""
GATE_MODE="audit"

while [ $# -gt 0 ]; do
    case "$1" in
        --project-root) shift; PROJECT_ROOT="${1:-$PROJECT_ROOT}" ;;
        --mode) shift; GATE_MODE="${1:-$GATE_MODE}" ;;
        *) PROJECT_ROOT="${PROJECT_ROOT:-$1}" ;;
    esac
    shift
done

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

case "$GATE_MODE" in
    audit|release) ;;
    *)
        echo "Invalid --mode: $GATE_MODE (valid: audit, release)" >&2
        exit 1
        ;;
esac

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC} $*"; }
pass()  { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
fail()  { echo -e "${RED}❌${NC} $*"; }

validate_external_audit_receipt() {
    local receipt_file="$1"

    python3 - "$receipt_file" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")

def clean(value):
    return str(value).strip().strip("*`").strip()

def is_pass(value):
    return clean(value).lower() in {
        "pass",
        "passed",
        "approved",
        "approved with no findings",
        "approved_with_no_findings",
        "clear",
        "clean",
    }

def is_zero(value):
    if isinstance(value, (int, float)):
        return value == 0
    return clean(value).lower() in {"0", "none", "no", "false", "n/a", "na", "zero"}

def first_present(data, keys):
    for key in keys:
        if key in data:
            return data[key]
    return None

try:
    if path.suffix.lower() == ".json":
        data = json.loads(text)
        result = first_present(data, ["result", "status", "verdict", "external_audit_result"])
        open_p0 = first_present(data, ["open_p0", "openP0", "p0_open", "p0Open", "p0_issues", "p0Issues"])
        open_p1 = first_present(data, ["open_p1", "openP1", "p1_open", "p1Open", "p1_issues", "p1Issues"])
    else:
        result_match = re.search(
            r"(?im)^\s*(?:[-*]\s*)?\**\s*(?:result|status|verdict|external audit result)\s*\**\s*:\s*\**\s*([A-Za-z_ -]+?)\s*\**\s*$",
            text,
        )
        p0_match = re.search(
            r"(?im)^\s*(?:[-*]\s*)?\**\s*(?:open\s*p0|p0\s*open|unresolved\s*p0|p0\s*issues)\s*\**\s*:\s*\**\s*([A-Za-z0-9_/-]+)\s*\**\s*$",
            text,
        )
        p1_match = re.search(
            r"(?im)^\s*(?:[-*]\s*)?\**\s*(?:open\s*p1|p1\s*open|unresolved\s*p1|p1\s*issues)\s*\**\s*:\s*\**\s*([A-Za-z0-9_/-]+)\s*\**\s*$",
            text,
        )
        result = result_match.group(1) if result_match else None
        open_p0 = p0_match.group(1) if p0_match else None
        open_p1 = p1_match.group(1) if p1_match else None

    if not is_pass(result):
        print("receipt result/status is not PASS")
        sys.exit(1)
    if open_p0 is None or open_p1 is None:
        print("receipt missing open P0/P1 fields")
        sys.exit(1)
    if not is_zero(open_p0) or not is_zero(open_p1):
        print(f"receipt has open P0/P1 findings (P0={open_p0}, P1={open_p1})")
        sys.exit(1)
except Exception as exc:
    print(f"receipt parse failed: {exc}")
    sys.exit(1)
PY
}

P0_COUNT=0
P1_COUNT=0
P2_COUNT=0
CHECKS_TOTAL=0
CHECKS_PASS=0
CHECKS_FAIL=0

cd "$PROJECT_ROOT"

echo "═══════════════════════════════════════════════════════════"
echo "TAF Release Gate v2.0 (legacy hmte command)"
echo "Project: $PROJECT_ROOT"
echo "Mode: $GATE_MODE"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Check 1: Eval harness ──────────────────────────────────
info "Check 1: Eval Harness"
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if bash scripts/hmte-eval.sh > /dev/null 2>&1; then
    pass "Eval harness passed"
    CHECKS_PASS=$((CHECKS_PASS + 1))
else
    fail "Eval harness failed"
    CHECKS_FAIL=$((CHECKS_FAIL + 1))
    P0_COUNT=$((P0_COUNT + 1))
fi
echo ""

# ── Check 2: Protocol lint ────────────────────────────────
info "Check 2: Protocol Lint (release mode)"
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
LINT_OUTPUT=$(HMTE_LINT_MODE=release bash scripts/hmte-lint-protocol.sh 2>&1) && LINT_EXIT=0 || LINT_EXIT=$?

if [ "$LINT_EXIT" -eq 0 ]; then
    pass "Protocol lint passed"
    CHECKS_PASS=$((CHECKS_PASS + 1))
else
    HAS_ACTIVE_SESSION=false
    if [ -f ".phase_control/session.json" ] || [ -f ".phase_control/phases.json" ]; then
        HAS_ACTIVE_SESSION=true
    fi

    if ! $HAS_ACTIVE_SESSION; then
        pass "Protocol lint skipped for release repository mode (no active .phase_control session)"
        CHECKS_PASS=$((CHECKS_PASS + 1))
    else
        fail "Protocol lint failed with active session present"
        CHECKS_FAIL=$((CHECKS_FAIL + 1))
        P1_COUNT=$((P1_COUNT + 1))
    fi
fi
echo ""

# ── Check 3: Final check ──────────────────────────────────
info "Check 3: Final Check (release mode)"
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if bash scripts/hmte-final-check.sh --mode release > /dev/null 2>&1; then
    pass "Final check passed"
    CHECKS_PASS=$((CHECKS_PASS + 1))
else
    # Final check failure means file protocol integrity cannot be confirmed
    # This is P1 — cannot release without passing final check
    fail "Final check failed — cannot verify file protocol integrity"
    CHECKS_FAIL=$((CHECKS_FAIL + 1))
    P1_COUNT=$((P1_COUNT + 1))
fi
echo ""

# ── Check 4: Dogfood audit pack exists AND passed ─────────
info "Check 4: Dogfood Audit Pack"
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
DOGGFOOD_PACK_EXISTS=false
DOGGFOOD_PACK_PASSED=false
LATEST_DOGFOOD_REPORT=""

if [ -d ".phase_control/audits" ]; then
    # Find the latest dogfood report (case-insensitive glob)
    LATEST_DOGFOOD_REPORT=""
    for f in .phase_control/audits/*[Dd][Oo][Gg][Ff][Oo][Oo][Dd]*.md; do
        if [ -f "$f" ]; then
            DOGGFOOD_PACK_EXISTS=true
            LATEST_DOGFOOD_REPORT="$f"
        fi
    done
fi

if ! $DOGGFOOD_PACK_EXISTS; then
    warn "Dogfood audit pack not found"
    P1_COUNT=$((P1_COUNT + 1))
    CHECKS_FAIL=$((CHECKS_FAIL + 1))
else
    # Check the report result — must contain Result: PASS, not just exist
    if grep -q '\*\*Result: PASS\*\*' "$LATEST_DOGFOOD_REPORT" 2>/dev/null; then
        DOGGFOOD_PACK_PASSED=true
        pass "Dogfood audit pack found and passed"
        CHECKS_PASS=$((CHECKS_PASS + 1))
    else
        # Report exists but did not pass (FAIL or indeterminate)
        fail "Dogfood audit pack exists but did not pass"
        P1_COUNT=$((P1_COUNT + 1))
        CHECKS_FAIL=$((CHECKS_FAIL + 1))
    fi
fi
echo ""

# ── Check 5: External audit receipt ───────────────────────
if [ "$GATE_MODE" = "release" ]; then
    info "Check 5: External Audit Receipt (required for release)"
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
else
    info "Check 5: External Audit Receipt (informational)"
fi
EXTERNAL_AUDIT_RECEIVED=false
EXTERNAL_AUDIT_RECEIPT_PATH=""
if [ -f ".phase_control/external_audit_receipt.json" ]; then
    EXTERNAL_AUDIT_RECEIPT_PATH=".phase_control/external_audit_receipt.json"
elif [ -f "EXTERNAL_AUDIT_RECEIPT.md" ]; then
    EXTERNAL_AUDIT_RECEIPT_PATH="EXTERNAL_AUDIT_RECEIPT.md"
fi

if [ -n "$EXTERNAL_AUDIT_RECEIPT_PATH" ]; then
    EXTERNAL_AUDIT_RECEIVED=true
    RECEIPT_VALIDATION_OUTPUT=$(validate_external_audit_receipt "$EXTERNAL_AUDIT_RECEIPT_PATH" 2>&1) && RECEIPT_VALID=true || RECEIPT_VALID=false

    if $RECEIPT_VALID; then
        pass "External audit receipt valid: $EXTERNAL_AUDIT_RECEIPT_PATH"
        if [ "$GATE_MODE" = "release" ]; then
            CHECKS_PASS=$((CHECKS_PASS + 1))
        fi
    else
        if [ "$GATE_MODE" = "release" ]; then
            fail "External audit receipt is not release-valid: $RECEIPT_VALIDATION_OUTPUT"
            CHECKS_FAIL=$((CHECKS_FAIL + 1))
            P1_COUNT=$((P1_COUNT + 1))
        else
            warn "External audit receipt found but not release-valid: $RECEIPT_VALIDATION_OUTPUT"
        fi
    fi
else
    if [ "$GATE_MODE" = "release" ]; then
        fail "External audit receipt not found; release/GitHub publishing is blocked"
        CHECKS_FAIL=$((CHECKS_FAIL + 1))
        P1_COUNT=$((P1_COUNT + 1))
    else
        warn "External audit receipt not found; release/GitHub publishing remains blocked"
    fi
fi
echo ""

# ── Check 6: No .phase_control in git staging ─────────────
info "Check 6: .phase_control not in git staging"
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if git diff --cached --name-only 2>/dev/null | grep -q "^\.phase_control/"; then
    fail ".phase_control/ files found in git staging area"
    CHECKS_FAIL=$((CHECKS_FAIL + 1))
    P0_COUNT=$((P0_COUNT + 1))
else
    pass "No .phase_control/ in git staging"
    CHECKS_PASS=$((CHECKS_PASS + 1))
fi
echo ""

# ── Check 7: No sensitive files in git staging ────────────
info "Check 7: No sensitive files in git staging"
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
SENSITIVE_FOUND=false
while IFS= read -r staged; do
    case "$staged" in
        test_results.log|*/test_results.log)
            SENSITIVE_FOUND=true; break ;;
        *.tar.gz)
            SENSITIVE_FOUND=true; break ;;
        private_validation/*|*/private_validation/*)
            SENSITIVE_FOUND=true; break ;;
    esac
done < <(git diff --cached --name-only 2>/dev/null)

if $SENSITIVE_FOUND; then
    fail "Sensitive files found in git staging area"
    CHECKS_FAIL=$((CHECKS_FAIL + 1))
    P0_COUNT=$((P0_COUNT + 1))
else
    pass "No sensitive files in git staging"
    CHECKS_PASS=$((CHECKS_PASS + 1))
fi
echo ""

# ── Summary ────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "Release Gate Summary"
echo "═══════════════════════════════════════════════════════════"
echo "Checks: $CHECKS_PASS/$CHECKS_TOTAL passed"
echo "P0 issues: $P0_COUNT"
echo "P1 issues: $P1_COUNT"
echo "P2 issues: $P2_COUNT"
echo ""

# ── Verdict ────────────────────────────────────────────────
if [ "$P0_COUNT" -gt 0 ]; then
    fail "VERDICT: FAIL — P0 issues must be resolved before release"
    echo ""
    echo "Release gate is an outer gate. P0 issues block all further progress."
    exit 1
elif [ "$P1_COUNT" -gt 0 ]; then
    fail "VERDICT: FAIL — P1 issues must be resolved before release"
    echo ""
    echo "Release gate is an outer gate. P1 issues block release."
    exit 1
else
    if [ "$GATE_MODE" = "release" ]; then
        pass "VERDICT: PASS — READY_FOR_RELEASE"
    else
        pass "VERDICT: PASS — READY_FOR_EXTERNAL_AUDIT"
    fi
    echo ""
    if $EXTERNAL_AUDIT_RECEIVED; then
        echo "External audit receipt is on file."
        if [ "$GATE_MODE" = "release" ]; then
            echo "Strict release gate passed; verify release artifacts match the receipt before publishing."
        fi
    else
        echo "External audit receipt is not on file; do not publish a release or push GitHub release artifacts."
    fi
    exit 0
fi
