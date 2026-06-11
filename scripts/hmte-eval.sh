#!/usr/bin/env bash
# hmte-eval.sh — Protocol Eval Harness MVP
# Version: 2.0.0
# Purpose: 验证 TriAgentFlow / TAF 协议和门禁是否真的生效

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVALS_DIR="$PROJECT_ROOT/evals"

PASS=0
FAIL=0

# v1.9 Required cases (fail-closed: missing required case = FAIL)
REQUIRED_V19_NEGATIVE_CASES=(
    "E001_missing_evidence.sh"
    "E004_multi_phase_missing_acceptance_criteria.sh"
    "E005_multi_phase_acceptance_criteria_not_array.sh"
    "E006_multi_phase_invalid_execution_mode.sh"
    "E007_multi_phase_parallel_worker_missing_fields.sh"
    "E008_release_gate_p0_blocking.sh"
    "E009_release_gate_p1_blocking.sh"
    "E010_release_gate_missing_dogfood.sh"
    "E011_audit_pack_invalid_mode.sh"
    "E012_audit_pack_core_gate_fail.sh"
    "E013_release_gate_lint_failure_blocking.sh"
    "E014_release_gate_final_check_failure_blocking.sh"
    "E015_release_gate_sensitive_tarball_blocking.sh"
    "E016_release_gate_failed_dogfood_pack_blocking.sh"
)

REQUIRED_V19_POSITIVE_CASES=(
    "E002_deprecated_schema.sh"
    "E003_valid_sequential.sh"
)

# v2.0 Required cases (Plan-Grounded Audit Governance)
REQUIRED_V20_CASES=(
    # Plan Contract/Lock (4 cases)
    "PC001_missing_plan_lock_blocks_start.sh"
    "PC002_plan_hash_mismatch_blocks_execution.sh"
    "PC003_plan_item_without_id_fails.sh"
    "PC004_required_tests_missing_from_plan_fails.sh"
    
    # Plan-to-Delegation Fidelity (12 cases)
    "PD001_worker_instruction_missing_plan_ref.sh"
    "PD002_leader_simplifies_worker_task_from_plan.sh"
    "PD003_worker_timeout_leader_downgrades_required_test.sh"
    "PD004_integration_tests_skipped_without_amendment.sh"
    "PD005_coverage_report_required_but_replaced_by_core_tests.sh"
    "PD006_previous_phase_tests_used_as_substitute_evidence.sh"
    "PD007_leader_simplifies_plan_item_into_smaller_task.sh"
    "PD008_integration_tests_skipped_with_fake_amendment.sh"
    "PD009_vague_plan_item_rejected.sh"
    "PD010_phases_json_drops_locked_plan_item.sh"
    "PD011_timeout_resplit_drops_required_test.sh"
    "PD012_worker_instruction_claims_full_plan_but_steps_partial.sh"
    
    # Verifier Mandate (10 cases)
    "VM001_verifier_instruction_missing_audit_plan_ref.sh"
    "VM002_verifier_instruction_omits_p0_plan_item.sh"
    "VM003_verifier_instruction_says_summary_only.sh"
    "VM004_verifier_instruction_skips_command_log.sh"
    "VM005_parallel_verifier_instruction_missing_one_shard.sh"
    "VM006_verifier_rubber_stamp_pass.sh"
    "VM007_verifier_instruction_omits_required_plan_item.sh"
    "VM008_verifier_instruction_limits_review_to_summary_only.sh"
    "VM009_verifier_mandate_omits_changed_file.sh"
    "VM010_verifier_instruction_restricts_to_summary_by_synonym.sh"
    
    # Evidence Anchoring (3 cases)
    "EV009_evidence_has_all_plan_ids_but_no_artifacts.sh"
    "EV010_worker_omits_required_test_from_tests_run.sh"
    "EV011_previous_phase_test_used_as_current_evidence.sh"
    
    # Anomaly (6 cases)
    "AN001_timeout_not_recorded_blocks_gate.sh"
    "AN002_skipped_required_test_without_disposition_blocks_gate.sh"
    "AN003_partial_test_pass_without_disposition_blocks_gate.sh"
    "AN004_basic_achievement_without_required_evidence_blocks_gate.sh"
    "AN009_p0_anomaly_accepted_risk_blocks_release.sh"
    "AN010_required_test_basic_achievement_escalates_to_p1.sh"
    
    # PASS Contradiction (6 cases)
    "PCON001_final_pass_conflicts_with_phase_partial_pass.sh"
    "PCON002_production_ready_with_unresolved_anomaly.sh"
    "PCON003_44_44_pass_hides_23_26_history.sh"
    "PCON004_release_pack_missing_failure_context.sh"
    "PCON005_final_summary_washes_failed_history.sh"
    "PCON009_final_report_structured_pass_conflicts_with_anomaly_ledger.sh"
    
    # Zero-Finding (4 cases)
    "ZF001_verdict_pass_without_zero_finding_justification.sh"
    "ZF002_zero_finding_missing_timeout_review.sh"
    "ZF003_three_pass_phases_without_justification_pending.sh"
    "ZF009_zero_finding_without_evidence_anchor_fails.sh"
)

# v2.0 Release Completion cases
REQUIRED_V20_RELEASE_CASES=(
    "E017_release_gate_requires_external_audit_receipt.sh"
)

run_eval() {
    local case_script="$1"
    local case_name="$(basename "$case_script")"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Running: $case_name"
    echo "═══════════════════════════════════════════════════════════"
    
    # New semantics: exit 0 = test passed, exit non-0 = test failed
    if bash "$case_script" > /dev/null 2>&1; then
        echo "✅ PASS: $case_name"
        PASS=$((PASS + 1))
    else
        echo "❌ FAIL: $case_name"
        FAIL=$((FAIL + 1))
    fi
}

echo "TAF Protocol Eval Harness v2.0.0"
echo "================================="
echo ""
echo "PROJECT_ROOT: $PROJECT_ROOT"
echo "EVALS_DIR: $EVALS_DIR"
echo ""

# Check if evals directory exists
if [ ! -d "$EVALS_DIR/cases" ]; then
    echo "❌ FATAL: evals/cases/ directory not found"
    echo "Expected: $EVALS_DIR/cases/"
    exit 1
fi

# v1.9 Negative cases (expect FAIL) - fail-closed
echo "Running v1.9 negative cases (expect FAIL)..."

for case_file in "${REQUIRED_V19_NEGATIVE_CASES[@]}"; do
    case_path="$EVALS_DIR/cases/$case_file"
    if [ -f "$case_path" ]; then
        run_eval "$case_path"
    else
        echo ""
        echo "❌ FATAL: Required v1.9 negative case missing: $case_file"
        echo "Path: $case_path"
        echo "Eval harness cannot pass with missing required cases (fail-closed)"
        exit 1
    fi
done

# v1.9 Positive cases (expect PASS) - fail-closed
echo ""
echo "Running v1.9 positive cases (expect PASS)..."

for case_file in "${REQUIRED_V19_POSITIVE_CASES[@]}"; do
    case_path="$EVALS_DIR/cases/$case_file"
    if [ -f "$case_path" ]; then
        run_eval "$case_path"
    else
        echo ""
        echo "❌ FATAL: Required v1.9 positive case missing: $case_file"
        echo "Path: $case_path"
        echo "Eval harness cannot pass with missing required cases (fail-closed)"
        exit 1
    fi
done

# v2.0 cases (Plan-Grounded Audit Governance) - fail-closed
echo ""
echo "Running v2.0 Plan-Grounded cases..."

for case_file in "${REQUIRED_V20_CASES[@]}"; do
    case_path="$EVALS_DIR/cases/$case_file"
    if [ -f "$case_path" ]; then
        run_eval "$case_path"
    else
        echo ""
        echo "❌ FATAL: Required v2.0 case missing: $case_file"
        echo "Path: $case_path"
        echo "Eval harness cannot pass with missing required cases (fail-closed)"
        exit 1
    fi
done

# v2.0 release completion cases - fail-closed
echo ""
echo "Running v2.0 Release Completion cases..."

for case_file in "${REQUIRED_V20_RELEASE_CASES[@]}"; do
    case_path="$EVALS_DIR/cases/$case_file"
    if [ -f "$case_path" ]; then
        run_eval "$case_path"
    else
        echo ""
        echo "❌ FATAL: Required v2.0 release case missing: $case_file"
        echo "Path: $case_path"
        echo "Eval harness cannot pass with missing required cases (fail-closed)"
        exit 1
    fi
done

# Summary
V19_TOTAL=$((${#REQUIRED_V19_NEGATIVE_CASES[@]} + ${#REQUIRED_V19_POSITIVE_CASES[@]}))
V20_TOTAL=$((${#REQUIRED_V20_CASES[@]} + ${#REQUIRED_V20_RELEASE_CASES[@]}))
EXPECTED_TOTAL=$((V19_TOTAL + V20_TOTAL))

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "  v1.9 cases: $V19_TOTAL"
echo "  v2.0 cases: $V20_TOTAL"
echo "  Total:      $EXPECTED_TOTAL"
echo "═══════════════════════════════════════════════════════════"

if [ $FAIL -eq 0 ]; then
    echo "✅ All eval cases passed"
    exit 0
else
    echo "❌ Some eval cases failed"
    exit 1
fi
