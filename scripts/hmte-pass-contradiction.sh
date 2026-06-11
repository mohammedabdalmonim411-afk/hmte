#!/usr/bin/env bash
set -uo pipefail

# TAF PASS Contradiction Detector v2.0
# 防止最终报告洗白历史问题

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Detect contradictions between final report and historical anomalies.

OPTIONS:
  --plan PATH              Path to plan markdown file (required)
  --anomaly-ledger PATH    Path to anomaly_ledger.json (default: .phase_control/anomaly_ledger.json)
  --final-report PATH      Path to final_report.json (optional)
  --evidence-dir PATH      Path to evidence directory (optional, for history check)
  --help                   Show this help message

EXAMPLES:
  # Check for contradictions
  $0 --plan HTE_v2.0_PROJECT_PLAN.md \\
     --anomaly-ledger .phase_control/anomaly_ledger.json
EOF
  exit 0
}

log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo "ℹ $1"; }

# Parse arguments
PLAN_PATH=""
ANOMALY_LEDGER_PATH=".phase_control/anomaly_ledger.json"
FINAL_REPORT_PATH=""
EVIDENCE_DIR=".phase_control/evidence"

while [[ $# -gt 0 ]]; do
  case $1 in
    --plan) PLAN_PATH="$2"; shift 2 ;;
    --anomaly-ledger) ANOMALY_LEDGER_PATH="$2"; shift 2 ;;
    --final-report) FINAL_REPORT_PATH="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

if [[ -z "$PLAN_PATH" ]]; then
  echo "Error: --plan is required"
  exit 1
fi

if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Error: Plan file not found: $PLAN_PATH"
  exit 1
fi

echo "=========================================="
echo "TAF PASS Contradiction Detector v2.0"
echo "=========================================="
echo "Plan: $PLAN_PATH"
echo "Anomaly Ledger: $ANOMALY_LEDGER_PATH"
echo ""

FAIL_COUNT=0
WARN_COUNT=0
CONTRADICTION_COUNT=0

if ! command -v jq &>/dev/null; then
  log_fail "jq is required but not installed"
  exit 1
fi

# Check 1: Check anomaly ledger exists and for unresolved anomalies
if [[ ! -f "$ANOMALY_LEDGER_PATH" ]]; then
  log_warn "Anomaly ledger not found: $ANOMALY_LEDGER_PATH"
  ((WARN_COUNT++))
else
  log_info "检查 anomaly ledger..."
  
  # Check for unresolved anomalies
  UNRESOLVED_COUNT=$(jq -r '[.entries[] | select(.status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  UNRESOLVED_COUNT=${UNRESOLVED_COUNT:-0}
  
  if [[ $UNRESOLVED_COUNT -gt 0 ]]; then
    log_fail "Found $UNRESOLVED_COUNT unresolved anomalies"
    ((FAIL_COUNT++))
    ((CONTRADICTION_COUNT++))
    
    # List unresolved anomalies
    jq -r '.entries[] | select(.status == "open") | "  - [\(.severity)] \(.entry_id): \(.description)"' "$ANOMALY_LEDGER_PATH" 2>/dev/null
  else
    log_pass "No unresolved anomalies"
  fi
  
  # Check for P0/P1 anomalies
  P0_ANOMALIES=$(jq -r '[.entries[] | select(.severity == "P0")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  P1_ANOMALIES=$(jq -r '[.entries[] | select(.severity == "P1")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  
  P0_ANOMALIES=${P0_ANOMALIES:-0}
  P1_ANOMALIES=${P1_ANOMALIES:-0}
  
  if [[ $P0_ANOMALIES -gt 0 ]]; then
    P0_OPEN=$(jq -r '[.entries[] | select(.severity == "P0" and .status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
    if [[ $P0_OPEN -gt 0 ]]; then
      log_fail "Found $P0_OPEN open P0 anomalies (must be resolved before PASS)"
      ((FAIL_COUNT++))
      ((CONTRADICTION_COUNT++))
    fi
  fi
  
  if [[ $P1_ANOMALIES -gt 0 ]]; then
    P1_OPEN=$(jq -r '[.entries[] | select(.severity == "P1" and .status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
    if [[ $P1_OPEN -gt 0 ]]; then
      log_warn "Found $P1_OPEN open P1 anomalies (should be resolved)"
      ((WARN_COUNT++))
    fi
  fi
  
  # Check 2: Check for history washing patterns
  log_info "检查历史洗白模式..."
  
  # Pattern 1: timeout anomalies
  TIMEOUT_COUNT=$(jq -r '[.entries[] | select(.anomaly_type | test("timeout"))] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  if [[ $TIMEOUT_COUNT -gt 0 ]]; then
    log_warn "Found $TIMEOUT_COUNT timeout anomalies in history"
    
    # Check if timeouts are all resolved with proper justification
    UNRESOLVED_TIMEOUTS=$(jq -r '[.entries[] | select(.anomaly_type | test("timeout")) | select(.status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
    if [[ $UNRESOLVED_TIMEOUTS -gt 0 ]]; then
      log_fail "Found $UNRESOLVED_TIMEOUTS unresolved timeout anomalies"
      ((FAIL_COUNT++))
      ((CONTRADICTION_COUNT++))
    fi
  fi
  
  # Pattern 2: partial test pass (e.g., "23/26 passed")
  PARTIAL_PASS_COUNT=$(jq -r '[.entries[] | select(.anomaly_type == "partial_test_pass")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  if [[ $PARTIAL_PASS_COUNT -gt 0 ]]; then
    log_info "Found $PARTIAL_PASS_COUNT partial test pass anomalies"
    
    # Extract descriptions to look for specific patterns
    PARTIAL_DESCRIPTIONS=$(jq -r '.entries[] | select(.anomaly_type == "partial_test_pass") | .description' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo "")
    
    if echo "$PARTIAL_DESCRIPTIONS" | grep -qE "[0-9]+/[0-9]+"; then
      log_warn "Partial test results found in history (e.g., '23/26 passed')"
      
      # Check if these are resolved
      UNRESOLVED_PARTIAL=$(jq -r '[.entries[] | select(.anomaly_type == "partial_test_pass") | select(.status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
      if [[ $UNRESOLVED_PARTIAL -gt 0 ]]; then
        log_fail "Found $UNRESOLVED_PARTIAL unresolved partial test pass issues"
        ((FAIL_COUNT++))
        ((CONTRADICTION_COUNT++))
      fi
    fi
  fi
  
  # Pattern 3: skipped tests
  SKIPPED_TEST_COUNT=$(jq -r '[.entries[] | select(.anomaly_type == "skipped_test")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  if [[ $SKIPPED_TEST_COUNT -gt 0 ]]; then
    log_info "Found $SKIPPED_TEST_COUNT skipped test anomalies"
    
    UNRESOLVED_SKIPPED=$(jq -r '[.entries[] | select(.anomaly_type == "skipped_test") | select(.status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
    if [[ $UNRESOLVED_SKIPPED -gt 0 ]]; then
      log_fail "Found $UNRESOLVED_SKIPPED unresolved skipped test issues"
      ((FAIL_COUNT++))
      ((CONTRADICTION_COUNT++))
    fi
  fi
  
  # Pattern 4: "basic_achievement" wording
  BASIC_ACHIEVEMENT_COUNT=$(jq -r '[.entries[] | select(.anomaly_type == "basic_achievement")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  if [[ $BASIC_ACHIEVEMENT_COUNT -gt 0 ]]; then
    log_warn "Found $BASIC_ACHIEVEMENT_COUNT 'basic_achievement' euphemism anomalies"
    
    UNRESOLVED_BASIC=$(jq -r '[.entries[] | select(.anomaly_type == "basic_achievement") | select(.status == "open")] | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
    if [[ $UNRESOLVED_BASIC -gt 0 ]]; then
      log_fail "Found $UNRESOLVED_BASIC unresolved 'basic_achievement' issues"
      ((FAIL_COUNT++))
      ((CONTRADICTION_COUNT++))
    fi
  fi
fi

# Check 3: Check final report (if provided)
if [[ -n "$FINAL_REPORT_PATH" && -f "$FINAL_REPORT_PATH" ]]; then
  log_info "检查 final report..."
  
  TESTS_TOTAL=$(jq -r '.tests_total // 0' "$FINAL_REPORT_PATH" 2>/dev/null || echo 0)
  TESTS_PASSED=$(jq -r '.tests_passed // 0' "$FINAL_REPORT_PATH" 2>/dev/null || echo 0)
  TESTS_FAILED=$(jq -r '.tests_failed // 0' "$FINAL_REPORT_PATH" 2>/dev/null || echo 0)
  TESTS_SKIPPED=$(jq -r '.tests_skipped // 0' "$FINAL_REPORT_PATH" 2>/dev/null || echo 0)
  PRODUCTION_READY=$(jq -r '.production_ready // false' "$FINAL_REPORT_PATH" 2>/dev/null || echo false)
  
  # Contradiction 1: claiming all pass but have unresolved anomalies
  if [[ $TESTS_PASSED -eq $TESTS_TOTAL && $TESTS_TOTAL -gt 0 && $UNRESOLVED_COUNT -gt 0 ]]; then
    log_fail "Contradiction: Final report claims all tests passed ($TESTS_PASSED/$TESTS_TOTAL), but have $UNRESOLVED_COUNT unresolved anomalies"
    ((FAIL_COUNT++))
    ((CONTRADICTION_COUNT++))
  fi
  
  # Contradiction 2: claiming all pass but report shows failed/skipped
  if [[ $TESTS_PASSED -eq $TESTS_TOTAL && $TESTS_TOTAL -gt 0 && ($TESTS_FAILED -gt 0 || $TESTS_SKIPPED -gt 0) ]]; then
    log_fail "Contradiction: Final report claims $TESTS_PASSED/$TESTS_TOTAL passed, but reports $TESTS_FAILED failed and $TESTS_SKIPPED skipped"
    ((FAIL_COUNT++))
    ((CONTRADICTION_COUNT++))
  fi
  
  # Contradiction 3: production-ready claim with unresolved anomalies
  if [[ "$PRODUCTION_READY" == "true" && $UNRESOLVED_COUNT -gt 0 ]]; then
    log_fail "Contradiction: Claiming production-ready but have $UNRESOLVED_COUNT unresolved anomalies"
    ((FAIL_COUNT++))
    ((CONTRADICTION_COUNT++))
  fi
  
  # Contradiction 4: Check if final numbers hide historical failures
  if [[ -d "$EVIDENCE_DIR" ]]; then
    log_info "检查历史 evidence 中的测试失败..."
    
    # Look for historical test failures in evidence files
    HISTORICAL_FAILURES=0
    for evidence_file in "$EVIDENCE_DIR"/*.json; do
      if [[ -f "$evidence_file" ]]; then
        PHASE_FAILED=$(jq -r '.tests_failed[]? // empty' "$evidence_file" 2>/dev/null | wc -l | tr -d ' ')
        PHASE_FAILED=${PHASE_FAILED:-0}
        HISTORICAL_FAILURES=$((HISTORICAL_FAILURES + PHASE_FAILED))
      fi
    done
    
    if [[ $HISTORICAL_FAILURES -gt 0 && $TESTS_FAILED -eq 0 ]]; then
      log_warn "Historical evidence shows $HISTORICAL_FAILURES test failures, but final report shows 0 failed"
      log_warn "Verify these failures were properly resolved, not just hidden"
      ((WARN_COUNT++))
    fi
  fi
fi

# Check 4: Look for "clean execution" or "no issues" claims with history
if [[ -f "$ANOMALY_LEDGER_PATH" ]]; then
  TOTAL_ANOMALIES=$(jq -r '.entries | length' "$ANOMALY_LEDGER_PATH" 2>/dev/null || echo 0)
  if [[ $TOTAL_ANOMALIES -gt 0 ]]; then
    log_info "Total anomalies in ledger: $TOTAL_ANOMALIES (resolved + unresolved)"
    
    if [[ -n "$FINAL_REPORT_PATH" && -f "$FINAL_REPORT_PATH" ]]; then
      # Check if report claims "no issues" or similar
      if grep -qi "clean execution\|no issues\|all passed\|100% pass" "$FINAL_REPORT_PATH" 2>/dev/null; then
        if [[ $TOTAL_ANOMALIES -gt 3 ]]; then
          log_warn "Report language suggests 'clean execution', but ledger shows $TOTAL_ANOMALIES anomalies in history"
          ((WARN_COUNT++))
        fi
      fi
    fi
  fi
fi

echo ""
echo "=========================================="
echo "验证结果"
echo "=========================================="
echo -e "${RED}✗ FAIL: $FAIL_COUNT${NC}"
echo -e "${YELLOW}⚠ WARN: $WARN_COUNT${NC}"
echo "Contradictions Found: $CONTRADICTION_COUNT"
echo ""

if [[ $CONTRADICTION_COUNT -gt 0 || $FAIL_COUNT -gt 0 ]]; then
  echo "❌ PASS Contradiction 检测失败"
  echo ""
  echo "修复建议："
  echo "1. 解决所有 unresolved anomalies"
  echo "2. 确保 final report 准确反映历史问题"
  echo "3. 不要用'44/44 PASS'掩盖'23/26 passed'的历史"
  echo "4. Production-ready 声明必须在所有问题解决后才能使用"
  echo "5. 确保 timeout/skipped/partial 问题都有明确的 resolution"
  exit 1
else
  echo "✅ PASS Contradiction 检测通过"
  exit 0
fi
