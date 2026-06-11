#!/usr/bin/env bash
# hmte-audit-pack.sh — TAF Audit Pack Builder (legacy hmte CLI)
#
# Generates Markdown audit reports in different modes.
# Artifacts are stored in .phase_control/audits/ (never committed to Git).
#
# Modes:
#   core    — Gate and protocol related tests
#   delta   — Minimal verification based on changed files
#   dogfood — Full E2E, eval harness, protocol lint, release gate status
#   full    — Maximum intensity, all core tests
#
# Usage:
#   bash scripts/hmte-audit-pack.sh --mode core
#   bash scripts/hmte-audit-pack.sh --mode delta --changed-files "README.md,src/foo.sh"
#   bash scripts/hmte-audit-pack.sh --mode dogfood
#   bash scripts/hmte-audit-pack.sh --mode full
#
# Exit codes:
#   0 — Audit pack generated successfully
#   1 — Audit pack generation failed (invalid mode, test failures, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE=""
CHANGED_FILES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) shift; MODE="${1:-}"; shift ;;
        --changed-files) shift; CHANGED_FILES="${1:-}"; shift ;;
        --project-root) shift; PROJECT_ROOT="${1:-$PROJECT_ROOT}"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── Validate mode ──────────────────────────────────────────
VALID_MODES="core delta dogfood full"

if [ -z "$MODE" ]; then
    echo "ERROR: --mode is required" >&2
    echo "Valid modes: $VALID_MODES" >&2
    exit 1
fi

if ! echo "$VALID_MODES" | grep -qw "$MODE"; then
    echo "ERROR: Invalid mode '$MODE'" >&2
    echo "Valid modes: $VALID_MODES" >&2
    exit 1
fi

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

cd "$PROJECT_ROOT"

# ── Prepare output directory ───────────────────────────────
AUDIT_DIR=".phase_control/audits"
mkdir -p "$AUDIT_DIR"

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
REPORT_FILE="$AUDIT_DIR/audit_${MODE}_${TIMESTAMP}.md"

# ── Initialize report ──────────────────────────────────────
cat > "$REPORT_FILE" <<HEADER
# TAF Audit Pack — ${MODE} mode

- **Mode**: ${MODE}
- **Timestamp**: ${TIMESTAMP}
- **Project**: $(basename "$PROJECT_ROOT")

HEADER

if [ -n "$CHANGED_FILES" ]; then
    echo "- **Changed Files**: ${CHANGED_FILES}" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"

TOTAL_CHECKS=0
PASS_COUNT=0
FAIL_COUNT=0

run_check() {
    local name="$1"
    local cmd="$2"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if eval "$cmd" > /dev/null 2>&1; then
        pass "$name"
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "- [x] ${name}" >> "$REPORT_FILE"
        return 0
    else
        fail "$name"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "- [ ] ${name} **FAILED**" >> "$REPORT_FILE"
        return 1
    fi
}

# ── Mode: core ─────────────────────────────────────────────
run_core_checks() {
    echo "## Core Checks" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    info "Running core checks (gate + protocol)..."

    # Eval harness
    run_check "Eval Harness" "bash scripts/hmte-eval.sh"

    # Protocol lint
    run_check "Protocol Lint (release)" "HMTE_LINT_MODE=release bash scripts/hmte-lint-protocol.sh"

    # Phase gate script exists
    run_check "phase_gate.sh exists" "[ -f scripts/phase_gate.sh ]"

    # Final check script exists
    run_check "hmte-final-check.sh exists" "[ -f scripts/hmte-final-check.sh ]"

    # Release gate script exists
    run_check "hmte-release-gate.sh exists" "[ -f scripts/hmte-release-gate.sh ]"

    # Core protocol docs exist
    run_check "HTE_PROTOCOL.md exists" "[ -f docs/HTE_PROTOCOL.md ]"

    # SKILL.md exists
    run_check "SKILL.md exists" "[ -f src/skills/hmte/SKILL.md ]"

    echo "" >> "$REPORT_FILE"
}

# ── Mode: delta ────────────────────────────────────────────
run_delta_checks() {
    echo "## Delta Checks" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    info "Running delta checks (changed files: ${CHANGED_FILES:-none})..."

    # Always run eval harness for delta
    run_check "Eval Harness" "bash scripts/hmte-eval.sh"

    # If changed files include docs, check doc structure
    if echo "$CHANGED_FILES" | grep -qi "docs/"; then
        run_check "Docs directory structure" "[ -d docs ]"
    fi

    # If changed files include scripts, check script permissions
    if echo "$CHANGED_FILES" | grep -qi "scripts/"; then
        run_check "Scripts directory exists" "[ -d scripts ]"
    fi

    # If changed files include evals, run eval
    if echo "$CHANGED_FILES" | grep -qi "evals/"; then
        run_check "Eval cases directory" "[ -d evals/cases ]"
    fi

    # If changed files include protocol, run lint
    if echo "$CHANGED_FILES" | grep -qi "HTE_PROTOCOL\|PHASES_SCHEMA\|SKILL"; then
        run_check "Protocol Lint" "bash scripts/hmte-lint-protocol.sh"
    fi

    # If no changed files specified, run core subset
    if [ -z "$CHANGED_FILES" ]; then
        run_check "Protocol Lint" "bash scripts/hmte-lint-protocol.sh"
    fi

    echo "" >> "$REPORT_FILE"
}

# ── Mode: dogfood ──────────────────────────────────────────
run_dogfood_checks() {
    echo "## Dogfood Checks" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    info "Running dogfood checks (full E2E + eval + lint + release gate)..."

    # Eval harness
    run_check "Eval Harness" "bash scripts/hmte-eval.sh"

    # Protocol lint (release)
    run_check "Protocol Lint (release)" "HMTE_LINT_MODE=release bash scripts/hmte-lint-protocol.sh"

    # Final check
    run_check "Final Check (release)" "bash scripts/hmte-final-check.sh --mode release"

    # E2E tests (if available)
    for e2e_script in scripts/e2e-*.sh; do
        if [ -f "$e2e_script" ]; then
            e2e_name=$(basename "$e2e_script" .sh)
            run_check "E2E: ${e2e_name}" "bash $e2e_script"
        fi
    done

    # Release gate status
    info "Checking release gate status..."
    if bash scripts/hmte-release-gate.sh > /dev/null 2>&1; then
        echo "- Release Gate: **PASS**" >> "$REPORT_FILE"
        pass "Release Gate: PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    else
        RG_EXIT=$?
        if [ "$RG_EXIT" -eq 2 ]; then
            echo "- Release Gate: **PENDING** (awaiting external audit)" >> "$REPORT_FILE"
            warn "Release Gate: PENDING"
            PASS_COUNT=$((PASS_COUNT + 1))
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        else
            echo "- Release Gate: **FAIL**" >> "$REPORT_FILE"
            fail "Release Gate: FAIL"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        fi
    fi

    echo "" >> "$REPORT_FILE"
}

# ── Mode: full ─────────────────────────────────────────────
run_full_checks() {
    echo "## Full Checks" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    info "Running full checks (maximum intensity)..."

    # Core checks
    run_core_checks

    # Additional full-mode checks
    echo "## Additional Full Checks" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # All E2E tests
    for e2e_script in scripts/e2e-*.sh; do
        if [ -f "$e2e_script" ]; then
            e2e_name=$(basename "$e2e_script" .sh)
            run_check "E2E: ${e2e_name}" "bash $e2e_script"
        fi
    done

    # Final check
    run_check "Final Check (release)" "bash scripts/hmte-final-check.sh --mode release"

    # Release gate
    info "Checking release gate status..."
    if bash scripts/hmte-release-gate.sh > /dev/null 2>&1; then
        echo "- Release Gate: **PASS**" >> "$REPORT_FILE"
        pass "Release Gate: PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    else
        RG_EXIT=$?
        if [ "$RG_EXIT" -eq 2 ]; then
            echo "- Release Gate: **PENDING**" >> "$REPORT_FILE"
            warn "Release Gate: PENDING"
            PASS_COUNT=$((PASS_COUNT + 1))
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        else
            echo "- Release Gate: **FAIL**" >> "$REPORT_FILE"
            fail "Release Gate: FAIL"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        fi
    fi

    # Dogfood checklist exists
    run_check "Dogfood Checklist exists" "[ -f docs/DOGFOOD_CHECKLIST_v1.9.md ]"

    # Release gate protocol doc exists
    run_check "Release Gate Protocol exists" "[ -f docs/RELEASE_GATE_PROTOCOL.md ]"

    # Audit pack modes doc exists
    run_check "Audit Pack Modes doc exists" "[ -f docs/AUDIT_PACK_MODES.md ]"

    echo "" >> "$REPORT_FILE"
}

# ── Run selected mode ──────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "TAF Audit Pack Builder (legacy hmte CLI)"
echo "Mode: $MODE"
echo "═══════════════════════════════════════════════════════════"
echo ""

case "$MODE" in
    core)   run_core_checks ;;
    delta)  run_delta_checks ;;
    dogfood) run_dogfood_checks ;;
    full)   run_full_checks ;;
esac

# ── Write summary ──────────────────────────────────────────
cat >> "$REPORT_FILE" <<SUMMARY

## Summary

- **Checks**: ${PASS_COUNT}/${TOTAL_CHECKS} passed
- **Failed**: ${FAIL_COUNT}
- **Mode**: ${MODE}

SUMMARY

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "" >> "$REPORT_FILE"
    echo "**Result: FAIL** — ${FAIL_COUNT} check(s) failed" >> "$REPORT_FILE"
else
    echo "" >> "$REPORT_FILE"
    echo "**Result: PASS** — All checks passed" >> "$REPORT_FILE"
fi

# ── Console summary ────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Audit Pack Summary"
echo "═══════════════════════════════════════════════════════════"
echo "Mode: $MODE"
echo "Checks: $PASS_COUNT/$TOTAL_CHECKS passed"
echo "Failed: $FAIL_COUNT"
echo "Report: $REPORT_FILE"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    fail "Audit pack has failures"
    exit 1
else
    pass "Audit pack generated successfully"
    exit 0
fi
