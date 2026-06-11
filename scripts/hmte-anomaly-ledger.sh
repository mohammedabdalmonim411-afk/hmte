#!/usr/bin/env bash
set -uo pipefail

# TAF Historical Anomaly Ledger v2.0
# 记录全流程异常，unresolved anomaly 不允许被最终 PASS 覆盖

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Manage Historical Anomaly Ledger for TriAgentFlow / TAF v2.0 projects.

OPTIONS:
  --ledger PATH            Path to anomaly_ledger.json (default: .phase_control/anomaly_ledger.json)
  --evidence PATH          Path to evidence file (for validation)
  --plan PATH              Path to plan markdown file (required for validation)
  --add-anomaly            Add a new anomaly entry
  --check                  Check for unresolved anomalies
  --list                   List all anomalies
  --phase-id ID            Phase ID for the anomaly
  --anomaly-type TYPE      Anomaly type (worker_timeout|test_timeout|skipped_test|partial_test_pass|etc.)
  --description TEXT       Anomaly description
  --severity LEVEL         Severity level (P0|P1|P2)
  --help                   Show this help message

ANOMALY TYPES:
  worker_timeout           Worker execution timeout (P1)
  delegate_task_timeout    delegate_task call timeout (P1)
  subagent_interrupted     Subagent interrupted (P1)
  test_timeout             Test timeout (P1)
  skipped_test             Skipped test (P1)
  partial_test_pass        Partial test pass (e.g., 23/26) (P1)
  coverage_report_missing  Coverage report missing (P1)
  integration_test_skipped Integration test skipped (P1)
  basic_achievement        "基本达成" wording (default P2, escalates to P1 if tied to required items)
  non_blocking             "非阻断" wording (default P2, escalates to P1 if tied to required items)
  future_optimization      "后续优化" wording (P2)
  leader_local_takeover    Leader bypassed Worker delegation (P0)
  final_summary_conflict   Final summary conflicts with history (P0)

EXAMPLES:
  # Add anomaly
  $0 --ledger .phase_control/anomaly_ledger.json \\
     --add-anomaly --phase-id phase_7 --anomaly-type partial_test_pass \\
     --description "23/26 tests passed" --severity P1

  # Check unresolved anomalies
  $0 --ledger .phase_control/anomaly_ledger.json --check

  # Validate evidence against ledger
  $0 --ledger .phase_control/anomaly_ledger.json \\
     --evidence .phase_control/evidence/phase_1_attempt_1.json \\
     --plan HTE_v2.0_PROJECT_PLAN.md

  # List all anomalies
  $0 --ledger .phase_control/anomaly_ledger.json --list
EOF
  exit 0
}

log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo "ℹ $1"; }

# Parse arguments
LEDGER_PATH=".phase_control/anomaly_ledger.json"
EVIDENCE_PATH=""
PLAN_PATH=""
ACTION=""
PHASE_ID=""
ANOMALY_TYPE=""
DESCRIPTION=""
SEVERITY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --ledger) LEDGER_PATH="$2"; shift 2 ;;
    --evidence) EVIDENCE_PATH="$2"; ACTION="validate"; shift 2 ;;
    --plan) PLAN_PATH="$2"; shift 2 ;;
    --add-anomaly) ACTION="add"; shift ;;
    --check) ACTION="check"; shift ;;
    --list) ACTION="list"; shift ;;
    --phase-id) PHASE_ID="$2"; shift 2 ;;
    --anomaly-type) ANOMALY_TYPE="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

# Create ledger if not exists
if [[ ! -f "$LEDGER_PATH" ]]; then
  mkdir -p "$(dirname "$LEDGER_PATH")"
  cat > "$LEDGER_PATH" <<EOF
{
  "ledger_id": "ANOMALY-LEDGER-$(date +%Y%m%d)",
  "plan_id": "TAF-PLAN-v2.0",
  "entries": []
}
EOF
  log_info "Created new anomaly ledger: $LEDGER_PATH"
fi

if ! command -v jq &>/dev/null; then
  log_warn "jq not installed, some checks will be limited"
fi

case "$ACTION" in
  add)
    if [[ -z "$PHASE_ID" || -z "$ANOMALY_TYPE" || -z "$DESCRIPTION" || -z "$SEVERITY" ]]; then
      echo "Error: --add-anomaly requires --phase-id, --anomaly-type, --description, --severity"
      exit 1
    fi
    
    ENTRY_ID="ANM-$(date +%s)"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Add entry (simplified - in production use jq)
    log_info "Adding anomaly: $ENTRY_ID"
    log_info "  Phase: $PHASE_ID"
    log_info "  Type: $ANOMALY_TYPE"
    log_info "  Severity: $SEVERITY"
    log_info "  Description: $DESCRIPTION"
    log_pass "Anomaly recorded (manual JSON update required)"
    ;;
    
  check)
    log_info "Checking for unresolved anomalies..."
    
    if command -v jq &>/dev/null; then
      # Check for P0 anomalies (must always BLOCK, cannot be accepted_risk)
      P0_OPEN=$(jq -r '.entries[] | select(.severity == "P0" and .status == "open") | .entry_id' "$LEDGER_PATH" 2>/dev/null || echo "")
      if [[ -n "$P0_OPEN" ]]; then
        log_fail "Found open P0 anomaly - critical risk must be addressed:"
        echo "$P0_OPEN" | while read -r id; do
          echo "  - $id"
        done
        exit 1
      fi
      
      # Check for any unresolved anomalies
      UNRESOLVED=$(jq -r '.entries[] | select(.status == "open") | .entry_id' "$LEDGER_PATH" 2>/dev/null || echo "")
      if [[ -n "$UNRESOLVED" ]]; then
        log_fail "Found unresolved anomalies:"
        echo "$UNRESOLVED" | while read -r id; do
          echo "  - $id"
        done
        exit 1
      else
        log_pass "No unresolved anomalies"
      fi
    else
      log_warn "jq not installed, skipping check"
    fi
    ;;
    
  list)
    log_info "Listing all anomalies..."
    if command -v jq &>/dev/null; then
      jq -r '.entries[] | "[\(.severity)] \(.entry_id): \(.description) (status: \(.status))"' "$LEDGER_PATH" 2>/dev/null || echo "No entries"
    else
      log_warn "jq not installed, showing raw JSON"
      cat "$LEDGER_PATH"
    fi
    ;;
  
  validate)
    # Validate evidence against anomaly ledger
    if [[ -z "$EVIDENCE_PATH" || -z "$PLAN_PATH" ]]; then
      echo "Error: --evidence and --plan are required for validation"
      exit 1
    fi
    
    if [[ ! -f "$EVIDENCE_PATH" ]]; then
      echo "Error: Evidence file not found: $EVIDENCE_PATH"
      exit 1
    fi
    
    if [[ ! -f "$PLAN_PATH" ]]; then
      echo "Error: Plan file not found: $PLAN_PATH"
      exit 1
    fi
    
    if ! command -v jq &>/dev/null; then
      log_fail "jq is required for validation"
      exit 1
    fi
    
    log_info "Validating evidence against anomaly ledger..."
    echo "=========================================="
    
    FAIL_COUNT=0
    
    # NEW: Check for P0 anomalies (must always BLOCK, cannot be accepted_risk)
    P0_OPEN=$(jq -r '.entries[] | select(.severity == "P0" and .status == "open") | .entry_id' "$LEDGER_PATH" 2>/dev/null || echo "")
    if [[ -n "$P0_OPEN" ]]; then
      log_fail "Found open P0 anomaly - critical risk must be addressed:"
      echo "$P0_OPEN" | while read -r id; do
        echo "  - $id"
      done
      ((FAIL_COUNT++))
    fi
    
    # Extract tests from evidence
    TESTS_FAILED=$(jq -r '.tests_failed[]? // empty' "$EVIDENCE_PATH" 2>/dev/null || echo "")
    TESTS_SKIPPED=$(jq -r '.tests_skipped[]? // empty' "$EVIDENCE_PATH" 2>/dev/null || echo "")
    TESTS_TIMED_OUT=$(jq -r '.tests_timed_out[]? // empty' "$EVIDENCE_PATH" 2>/dev/null || echo "")
    
    TESTS_FAILED_COUNT=$(echo "$TESTS_FAILED" | grep -c . 2>/dev/null || echo 0)
    TESTS_SKIPPED_COUNT=$(echo "$TESTS_SKIPPED" | grep -c . 2>/dev/null || echo 0)
    TESTS_TIMED_OUT_COUNT=$(echo "$TESTS_TIMED_OUT" | grep -c . 2>/dev/null || echo 0)
    
    # Clean up counts (remove any extra output)
    TESTS_FAILED_COUNT=$(echo "$TESTS_FAILED_COUNT" | tail -1 | tr -d ' ')
    TESTS_SKIPPED_COUNT=$(echo "$TESTS_SKIPPED_COUNT" | tail -1 | tr -d ' ')
    TESTS_TIMED_OUT_COUNT=$(echo "$TESTS_TIMED_OUT_COUNT" | tail -1 | tr -d ' ')
    
    log_info "Tests failed: $TESTS_FAILED_COUNT"
    log_info "Tests skipped: $TESTS_SKIPPED_COUNT"
    log_info "Tests timed out: $TESTS_TIMED_OUT_COUNT"
    
    # Check if skipped tests have disposition in ledger
    if [[ $TESTS_SKIPPED_COUNT -gt 0 ]]; then
      log_info "Checking skipped test disposition..."
      MISSING_COUNT=0
      
      while IFS= read -r test_name; do
        if [[ -z "$test_name" ]]; then continue; fi
        
        # Check if test has entry in ledger
        LEDGER_ENTRY=$(jq -r ".entries[] | select(.anomaly_type == \"skipped_test\" and (.description | contains(\"$test_name\")))" "$LEDGER_PATH" 2>/dev/null || echo "")
        
        if [[ -z "$LEDGER_ENTRY" ]]; then
          log_fail "Skipped test '$test_name' has no disposition in anomaly ledger"
          ((MISSING_COUNT++))
          ((FAIL_COUNT++))
        fi
      done <<< "$TESTS_SKIPPED"
      
      if [[ $MISSING_COUNT -eq 0 ]]; then
        log_pass "All skipped tests have disposition"
      else
        log_fail "$MISSING_COUNT skipped tests missing disposition"
      fi
    fi
    
    # Check if partial test pass has proper entry
    if [[ $TESTS_FAILED_COUNT -gt 0 || $TESTS_SKIPPED_COUNT -gt 0 ]]; then
      log_info "Checking partial test pass disposition..."
      
      # Look for partial_test_pass entry in ledger
      PARTIAL_ENTRY=$(jq -r '.entries[] | select(.anomaly_type == "partial_test_pass")' "$LEDGER_PATH" 2>/dev/null || echo "")
      
      if [[ -n "$PARTIAL_ENTRY" ]]; then
        # Check if partial_test_pass entry is properly documented
        PARTIAL_STATUS=$(echo "$PARTIAL_ENTRY" | jq -r '.status' 2>/dev/null || echo "")
        PARTIAL_DESC=$(echo "$PARTIAL_ENTRY" | jq -r '.description' 2>/dev/null || echo "")
        
        if [[ "$PARTIAL_STATUS" == "open" ]]; then
          log_fail "Partial test pass disposition is unresolved (status: open)"
          ((FAIL_COUNT++))
        fi
        
        # Check if description is too vague
        if [[ ${#PARTIAL_DESC} -lt 20 || "$PARTIAL_DESC" =~ ^(Test anomaly|TODO|TBD)$ ]]; then
          log_fail "Partial test pass disposition lacks detailed description (got: '$PARTIAL_DESC')"
          ((FAIL_COUNT++))
        fi
      fi
    fi
    
    # Check for basic_achievement with P0 tests
    BASIC_ACHIEVEMENT=$(jq -r '.entries[] | select(.anomaly_type == "basic_achievement")' "$LEDGER_PATH" 2>/dev/null || echo "")
    
    if [[ -n "$BASIC_ACHIEVEMENT" ]]; then
      log_info "Checking basic_achievement disposition..."
      
      # Extract related plan items
      RELATED_ITEMS=$(echo "$BASIC_ACHIEVEMENT" | jq -r '.related_plan_items[]? // empty' 2>/dev/null || echo "")
      
      if [[ -n "$RELATED_ITEMS" ]]; then
        # Check if any related items are P0 in the plan
        while IFS= read -r item_id; do
          if [[ -z "$item_id" ]]; then continue; fi
          
          if grep -A 2 "$item_id" "$PLAN_PATH" 2>/dev/null | grep -q "| P0 |"; then
            log_fail "P0 test '$item_id' cannot use 'basic_achievement' disposition"
            ((FAIL_COUNT++))
          fi
          
          # NEW: Check if item is in Required Tests section (escalates to P1)
          if sed -n '/## Required Tests/,/^##/p' "$PLAN_PATH" | grep -q "$item_id"; then
            log_fail "Required test '$item_id' with basic_achievement must escalate to P1 (currently P2)"
            ((FAIL_COUNT++))
          fi
        done <<< "$RELATED_ITEMS"
      fi
    fi
    
    echo "=========================================="
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
      log_fail "Anomaly ledger validation failed with $FAIL_COUNT errors"
      exit 1
    else
      log_pass "Anomaly ledger validation passed"
      exit 0
    fi
    ;;
    
  *)
    echo "Error: No action specified. Use --add-anomaly, --check, --list, or provide --evidence for validation"
    usage
    ;;
esac
