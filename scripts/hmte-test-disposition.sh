#!/usr/bin/env bash
set -uo pipefail

# TAF Failed/Skipped Test Disposition Gate v2.0
# 任何 failed/skipped/timeout test 都必须有处置记录

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Check Failed/Skipped Test Disposition for TriAgentFlow / TAF v2.0 projects.

OPTIONS:
  --evidence PATH          Path to evidence JSON (required)
  --plan PATH              Path to plan markdown file (required)
  --plan-lock PATH         Path to plan_lock.json (default: .phase_control/plan_lock.json)
  --disposition PATH       Path to test_dispositions.json (optional)
  --anomaly-ledger PATH    Path to anomaly_ledger.json (fallback for disposition check)
  --help                   Show this help message

EXAMPLES:
  # Check test disposition
  $0 --evidence .phase_control/evidence/phase_7_attempt_1.json \\
     --plan HTE_v2.0_PROJECT_PLAN.md
EOF
  exit 0
}

log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo "ℹ $1"; }

# Parse arguments
EVIDENCE_PATH=""
PLAN_PATH=""
PLAN_LOCK_PATH=".phase_control/plan_lock.json"
DISPOSITION_PATH=""
ANOMALY_LEDGER_PATH=".phase_control/anomaly_ledger.json"

while [[ $# -gt 0 ]]; do
  case $1 in
    --evidence) EVIDENCE_PATH="$2"; shift 2 ;;
    --plan) PLAN_PATH="$2"; shift 2 ;;
    --plan-lock) PLAN_LOCK_PATH="$2"; shift 2 ;;
    --disposition) DISPOSITION_PATH="$2"; shift 2 ;;
    --anomaly-ledger) ANOMALY_LEDGER_PATH="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

if [[ -z "$EVIDENCE_PATH" || -z "$PLAN_PATH" ]]; then
  echo "Error: --evidence and --plan are required"
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

echo "=========================================="
echo "TAF Test Disposition Gate v2.0"
echo "=========================================="
echo "Evidence: $EVIDENCE_PATH"
echo "Plan: $PLAN_PATH"
echo ""

FAIL_COUNT=0
WARN_COUNT=0

if ! command -v jq &>/dev/null; then
  log_fail "jq is required but not installed"
  exit 1
fi

# Check 1: Extract tests from evidence
log_info "检查 evidence 中的测试状态..."

TESTS_FAILED=$(jq -r '.tests_failed[]? // empty' "$EVIDENCE_PATH" 2>/dev/null)
TESTS_SKIPPED=$(jq -r '.tests_skipped[]? // empty' "$EVIDENCE_PATH" 2>/dev/null)
TESTS_TIMED_OUT=$(jq -r '.tests_timed_out[]? // empty' "$EVIDENCE_PATH" 2>/dev/null)

count_lines() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo 0
  else
    printf '%s\n' "$value" | grep -c . || true
  fi
}

TESTS_FAILED_COUNT=$(count_lines "$TESTS_FAILED")
TESTS_SKIPPED_COUNT=$(count_lines "$TESTS_SKIPPED")
TESTS_TIMED_OUT_COUNT=$(count_lines "$TESTS_TIMED_OUT")

log_info "Tests failed: $TESTS_FAILED_COUNT"
log_info "Tests skipped: $TESTS_SKIPPED_COUNT"
log_info "Tests timed out: $TESTS_TIMED_OUT_COUNT"

# Check 2: Verify dispositions exist for failed/skipped/timed-out tests
TOTAL_ISSUES=$((TESTS_FAILED_COUNT + TESTS_SKIPPED_COUNT + TESTS_TIMED_OUT_COUNT))

if [[ $TOTAL_ISSUES -eq 0 ]]; then
  log_pass "No failed/skipped/timed-out tests requiring disposition"
else
  log_info "检查 disposition 记录..."
  
  # Try to find dispositions in test_dispositions.json or anomaly_ledger.json
  DISPOSITION_SOURCE=""
  if [[ -n "$DISPOSITION_PATH" && -f "$DISPOSITION_PATH" ]]; then
    DISPOSITION_SOURCE="$DISPOSITION_PATH"
    log_info "Using disposition file: $DISPOSITION_PATH"
  elif [[ -f "$ANOMALY_LEDGER_PATH" ]]; then
    DISPOSITION_SOURCE="$ANOMALY_LEDGER_PATH"
    log_info "Using anomaly ledger as disposition source: $ANOMALY_LEDGER_PATH"
  fi
  
  if [[ -z "$DISPOSITION_SOURCE" ]]; then
    log_fail "No disposition source found (test_dispositions.json or anomaly_ledger.json)"
    log_fail "$TOTAL_ISSUES tests require disposition but no disposition records found"
    ((FAIL_COUNT++))
  else
    # Check failed tests
    if [[ $TESTS_FAILED_COUNT -gt 0 ]]; then
      log_info "Checking dispositions for $TESTS_FAILED_COUNT failed tests..."
      MISSING_DISPOSITION=0
      
      while IFS= read -r test_name; do
        if [[ -z "$test_name" ]]; then continue; fi
        
        # Check if test has disposition in source
        if ! grep -q "$test_name" "$DISPOSITION_SOURCE" 2>/dev/null; then
          log_fail "Failed test '$test_name' has no disposition record"
          ((MISSING_DISPOSITION++))
        else
          # Check if disposition has justification and severity
          DISPOSITION_ENTRY=$(grep -A 10 "$test_name" "$DISPOSITION_SOURCE" 2>/dev/null || echo "")
          
          if ! echo "$DISPOSITION_ENTRY" | grep -q "justification\|description"; then
            log_fail "Failed test '$test_name' disposition missing justification"
            ((MISSING_DISPOSITION++))
          elif ! echo "$DISPOSITION_ENTRY" | grep -q "severity"; then
            log_fail "Failed test '$test_name' disposition missing severity"
            ((MISSING_DISPOSITION++))
          fi
        fi
      done <<< "$TESTS_FAILED"
      
      if [[ $MISSING_DISPOSITION -gt 0 ]]; then
        log_fail "$MISSING_DISPOSITION failed tests missing proper disposition"
        ((FAIL_COUNT++))
      else
        log_pass "All failed tests have proper disposition"
      fi
    fi
    
    # Check skipped tests
    if [[ $TESTS_SKIPPED_COUNT -gt 0 ]]; then
      log_info "Checking dispositions for $TESTS_SKIPPED_COUNT skipped tests..."
      MISSING_DISPOSITION=0
      
      while IFS= read -r test_name; do
        if [[ -z "$test_name" ]]; then continue; fi
        
        if ! grep -q "$test_name" "$DISPOSITION_SOURCE" 2>/dev/null; then
          log_fail "Skipped test '$test_name' has no disposition record"
          ((MISSING_DISPOSITION++))
        else
          # Check if disposition has justification and severity
          DISPOSITION_ENTRY=$(grep -A 10 "$test_name" "$DISPOSITION_SOURCE" 2>/dev/null || echo "")
          
          if ! echo "$DISPOSITION_ENTRY" | grep -q "justification\|description"; then
            log_fail "Skipped test '$test_name' disposition missing justification"
            ((MISSING_DISPOSITION++))
          elif ! echo "$DISPOSITION_ENTRY" | grep -q "severity"; then
            log_fail "Skipped test '$test_name' disposition missing severity"
            ((MISSING_DISPOSITION++))
          fi
        fi
      done <<< "$TESTS_SKIPPED"
      
      if [[ $MISSING_DISPOSITION -gt 0 ]]; then
        log_fail "$MISSING_DISPOSITION skipped tests missing proper disposition"
        ((FAIL_COUNT++))
      else
        log_pass "All skipped tests have proper disposition"
      fi
    fi
    
    # Check timed out tests
    if [[ $TESTS_TIMED_OUT_COUNT -gt 0 ]]; then
      log_info "Checking dispositions for $TESTS_TIMED_OUT_COUNT timed-out tests..."
      MISSING_DISPOSITION=0
      
      while IFS= read -r test_name; do
        if [[ -z "$test_name" ]]; then continue; fi
        
        if ! grep -q "$test_name" "$DISPOSITION_SOURCE" 2>/dev/null; then
          log_fail "Timed-out test '$test_name' has no disposition record"
          ((MISSING_DISPOSITION++))
        fi
      done <<< "$TESTS_TIMED_OUT"
      
      if [[ $MISSING_DISPOSITION -gt 0 ]]; then
        log_fail "$MISSING_DISPOSITION timed-out tests missing disposition"
        ((FAIL_COUNT++))
      else
        log_pass "All timed-out tests have disposition"
      fi
    fi
  fi
fi

# Check 3: P0 tests with basic_achievement disposition
log_info "检查 P0 tests 不能使用 basic_achievement disposition..."

# Extract P0 tests from plan
P0_TESTS=$(grep -A 5 "| P0 |" "$PLAN_PATH" 2>/dev/null | grep -o "T-[0-9]\+" || echo "")

if [[ -n "$P0_TESTS" && -f "$ANOMALY_LEDGER_PATH" ]]; then
  INVALID_P0_DISPOSITION=0
  
  while IFS= read -r test_id; do
    if [[ -z "$test_id" ]]; then continue; fi
    
    # Check if this P0 test has basic_achievement disposition
    if grep -A 10 "$test_id" "$ANOMALY_LEDGER_PATH" 2>/dev/null | grep -q "basic_achievement"; then
      log_fail "P0 test '$test_id' cannot use 'basic_achievement' disposition"
      ((INVALID_P0_DISPOSITION++))
    fi
  done <<< "$P0_TESTS"
  
  if [[ $INVALID_P0_DISPOSITION -gt 0 ]]; then
    log_fail "$INVALID_P0_DISPOSITION P0 tests have invalid 'basic_achievement' disposition"
    ((FAIL_COUNT++))
  else
    log_pass "No P0 tests using 'basic_achievement' disposition"
  fi
fi

# Check 4: Required tests from plan
log_info "检查 Required Tests 是否执行..."
if grep -q "Required Tests\|Required Negative Tests" "$PLAN_PATH"; then
  log_info "Found Required Tests section in plan (detailed check requires plan parsing)"
else
  log_warn "No Required Tests section found in plan"
  ((WARN_COUNT++))
fi

echo ""
echo "=========================================="
echo "验证结果"
echo "=========================================="
echo -e "${RED}✗ FAIL: $FAIL_COUNT${NC}"
echo -e "${YELLOW}⚠ WARN: $WARN_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "❌ Test Disposition 验证失败"
  echo ""
  echo "修复建议："
  echo "1. 为所有 failed/skipped/timeout tests 添加 disposition 记录"
  echo "2. 在 test_dispositions.json 或 anomaly_ledger.json 中记录原因和处置决定"
  echo "3. 确保 disposition 包含 justification 和 severity"
  echo "4. P0 tests 不能使用 'basic_achievement' disposition"
  echo "5. 如果测试降级需要 plan amendment 授权"
  exit 1
else
  echo "✅ Test Disposition 验证通过"
  exit 0
fi
