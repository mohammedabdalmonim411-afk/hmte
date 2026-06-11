#!/usr/bin/env bash
# E017: Strict release gate requires an external audit receipt.
#
# Default audit mode may pass without the receipt because it means
# READY_FOR_EXTERNAL_AUDIT. Strict release mode must fail until the
# external audit receipt exists, then it may report READY_FOR_RELEASE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/scripts" "$TEMP_DIR/.phase_control/audits"
cp "$PROJECT_ROOT/scripts/hmte-release-gate.sh" "$TEMP_DIR/scripts/"

cat > "$TEMP_DIR/scripts/hmte-eval.sh" <<'EVAL'
#!/bin/bash
exit 0
EVAL
chmod +x "$TEMP_DIR/scripts/hmte-eval.sh"

cat > "$TEMP_DIR/scripts/hmte-lint-protocol.sh" <<'LINT'
#!/bin/bash
exit 0
LINT
chmod +x "$TEMP_DIR/scripts/hmte-lint-protocol.sh"

cat > "$TEMP_DIR/scripts/hmte-final-check.sh" <<'FCHECK'
#!/bin/bash
exit 0
FCHECK
chmod +x "$TEMP_DIR/scripts/hmte-final-check.sh"

cat > "$TEMP_DIR/.phase_control/audits/TAF_v2.0_FINAL_DOGFOOD_AUDIT.md" <<'REPORT'
# TAF v2.0 Dogfood Audit

**Result: PASS**
REPORT

cd "$TEMP_DIR"
git init -q

AUDIT_OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1)
AUDIT_EXIT=$?

if [ "$AUDIT_EXIT" -ne 0 ]; then
    echo "FAIL: default audit mode should pass without external audit receipt"
    echo "$AUDIT_OUTPUT"
    exit 1
fi

if ! echo "$AUDIT_OUTPUT" | grep -q "VERDICT: PASS — READY_FOR_EXTERNAL_AUDIT"; then
    echo "FAIL: default audit mode did not report READY_FOR_EXTERNAL_AUDIT"
    echo "$AUDIT_OUTPUT"
    exit 1
fi

RELEASE_OUTPUT=$(bash scripts/hmte-release-gate.sh --mode release --project-root "$TEMP_DIR" 2>&1) && RELEASE_EXIT=0 || RELEASE_EXIT=$?

if [ "$RELEASE_EXIT" -eq 0 ]; then
    echo "FAIL: strict release mode passed without external audit receipt"
    echo "$RELEASE_OUTPUT"
    exit 1
fi

if echo "$RELEASE_OUTPUT" | grep -q "VERDICT: PASS"; then
    echo "FAIL: strict release mode produced PASS without external audit receipt"
    echo "$RELEASE_OUTPUT"
    exit 1
fi

if ! echo "$RELEASE_OUTPUT" | grep -qiE "external audit receipt|P1"; then
    echo "FAIL: strict release mode did not explain missing receipt/P1"
    echo "$RELEASE_OUTPUT"
    exit 1
fi

cat > "$TEMP_DIR/EXTERNAL_AUDIT_RECEIPT.md" <<'RECEIPT'
# External Audit Receipt

- Result: PASS
- Open P0: 0
- Open P1: 1
RECEIPT

BAD_RECEIPT_OUTPUT=$(bash scripts/hmte-release-gate.sh --mode release --project-root "$TEMP_DIR" 2>&1) && BAD_RECEIPT_EXIT=0 || BAD_RECEIPT_EXIT=$?

if [ "$BAD_RECEIPT_EXIT" -eq 0 ]; then
    echo "FAIL: strict release mode passed with unresolved external P1"
    echo "$BAD_RECEIPT_OUTPUT"
    exit 1
fi

if ! echo "$BAD_RECEIPT_OUTPUT" | grep -qiE "open P0/P1|P0=|P1="; then
    echo "FAIL: strict release mode did not explain unresolved external P0/P1"
    echo "$BAD_RECEIPT_OUTPUT"
    exit 1
fi

cat > "$TEMP_DIR/EXTERNAL_AUDIT_RECEIPT.md" <<'RECEIPT'
# External Audit Receipt

- Result: PASS
- Open P0: 0
- Open P1: 0
RECEIPT

RELEASE_WITH_RECEIPT_OUTPUT=$(bash scripts/hmte-release-gate.sh --mode release --project-root "$TEMP_DIR" 2>&1)
RELEASE_WITH_RECEIPT_EXIT=$?

if [ "$RELEASE_WITH_RECEIPT_EXIT" -ne 0 ]; then
    echo "FAIL: strict release mode should pass when receipt exists and all checks pass"
    echo "$RELEASE_WITH_RECEIPT_OUTPUT"
    exit 1
fi

if ! echo "$RELEASE_WITH_RECEIPT_OUTPUT" | grep -q "VERDICT: PASS — READY_FOR_RELEASE"; then
    echo "FAIL: strict release mode did not report READY_FOR_RELEASE with receipt"
    echo "$RELEASE_WITH_RECEIPT_OUTPUT"
    exit 1
fi

echo "PASS: E017 — strict release mode requires external audit receipt"
exit 0
