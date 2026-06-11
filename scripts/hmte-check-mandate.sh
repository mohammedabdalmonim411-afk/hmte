#!/usr/bin/env bash
# hmte-check-mandate.sh - Verifier Mandate Contract checker
# Part of TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check Verifier Mandate Contract for Verifier instructions and verdicts.

OPTIONS:
  --instruction PATH       Path to Verifier instruction JSON
  --verdict PATH           Path to Verifier verdict JSON
  --plan PATH              Path to plan markdown file (required)
  --plan-lock PATH         Path to plan_lock.json (default: .phase_control/plan_lock.json)
  --anomaly-ledger PATH    Path to anomaly_ledger.json (for zero-finding check)
  --check-zero-finding     Check zero-finding justification in verdict
  --help                   Show this help message

EXAMPLES:
  # Check Verifier instruction
  $(basename "$0") --instruction .phase_control/verifier_instructions/phase_1.json \\
    --plan HTE_v2.0_PROJECT_PLAN.md

  # Check Verifier verdict with zero-finding validation
  $(basename "$0") --verdict .phase_control/verdicts/phase_1_verdict.json \\
    --plan HTE_v2.0_PROJECT_PLAN.md --check-zero-finding \\
    --anomaly-ledger .phase_control/anomaly_ledger.json

EXIT CODES:
  0 - Success
  1 - Mandate check failed
  2 - Invalid arguments
EOF
}

# Parse arguments
INSTRUCTION_FILE=""
VERDICT_FILE=""
PLAN_FILE=""
PLAN_LOCK_FILE=".phase_control/plan_lock.json"
ANOMALY_LEDGER_FILE=""
CHECK_ZERO_FINDING=false
EVIDENCE_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --instruction)
      INSTRUCTION_FILE="$2"
      shift 2
      ;;
    --verdict)
      VERDICT_FILE="$2"
      shift 2
      ;;
    --plan)
      PLAN_FILE="$2"
      shift 2
      ;;
    --plan-lock)
      PLAN_LOCK_FILE="$2"
      shift 2
      ;;
    --anomaly-ledger)
      ANOMALY_LEDGER_FILE="$2"
      shift 2
      ;;
    --check-zero-finding)
      CHECK_ZERO_FINDING=true
      shift
      ;;
    --evidence)
      EVIDENCE_FILE="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate required arguments
if [[ -z "$PLAN_FILE" ]]; then
  echo -e "${RED}Error: --plan is required${NC}" >&2
  usage
  exit 2
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo -e "${RED}Error: Plan file not found: $PLAN_FILE${NC}" >&2
  exit 1
fi

if [[ -z "$INSTRUCTION_FILE" && -z "$VERDICT_FILE" ]]; then
  echo -e "${RED}Error: Either --instruction or --verdict is required${NC}" >&2
  usage
  exit 2
fi

# Forbidden shortcuts
FORBIDDEN_SHORTCUTS=(
  "summary-only review"
  "summary only"
  "spot check only"
  "skip command log"
  "trust Worker claim"
  "obvious issues only"
  "quick review only"
  "ignore slow tests"
  "ignore skipped tests"
)

# Check instruction mandate
check_instruction_mandate() {
  local instruction_file="$1"
  local plan_file="$2"
  local plan_lock_file="$3"
  local errors=0

  echo "Checking Instruction Mandate: $instruction_file"
  echo "=========================================="

  if [[ ! -f "$instruction_file" ]]; then
    echo -e "${RED}✗ Instruction file not found: $instruction_file${NC}"
    return 1
  fi

  # Check if instruction has audit_plan_ref
  if ! grep -q '"audit_plan_ref"' "$instruction_file"; then
    echo -e "${RED}✗ Instruction missing audit_plan_ref${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ Instruction has audit_plan_ref${NC}"
  fi

  # Check if audit_plan_ref has plan_hash
  if ! grep -q '"plan_hash"' "$instruction_file"; then
    echo -e "${RED}✗ audit_plan_ref missing plan_hash${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ audit_plan_ref has plan_hash${NC}"
  fi

  # Check if audit_plan_ref has plan_item_ids_to_audit
  if ! grep -q '"plan_item_ids_to_audit"' "$instruction_file"; then
    echo -e "${RED}✗ audit_plan_ref missing plan_item_ids_to_audit${NC}"
    ((errors++))
  else
    local item_count=$(grep -A 20 '"plan_item_ids_to_audit"' "$instruction_file" | grep -o '"[A-Z]-[0-9]\+"' | wc -l | tr -d ' ')
    if [[ "$item_count" == "0" ]]; then
      echo -e "${RED}✗ plan_item_ids_to_audit is empty${NC}"
      ((errors++))
    else
      echo -e "${GREEN}✓ plan_item_ids_to_audit has $item_count items${NC}"
    fi
  fi

  # Check for forbidden shortcuts
  local shortcuts_found=0
  for shortcut in "${FORBIDDEN_SHORTCUTS[@]}"; do
    if grep -qi "$shortcut" "$instruction_file"; then
      echo -e "${RED}✗ Found forbidden shortcut: \"$shortcut\"${NC}"
      ((errors++))
      ((shortcuts_found++))
    fi
  done
  
  if [[ $shortcuts_found -eq 0 ]]; then
    echo -e "${GREEN}✓ No forbidden shortcuts found${NC}"
  fi

  # Check if plan_hash matches locked hash
  if [[ -f "$plan_lock_file" ]]; then
    local locked_hash=$(grep -o '"plan_hash": *"[^"]*"' "$plan_lock_file" | sed 's/"plan_hash": *"\(.*\)"/\1/' || echo "")
    local instruction_hash=$(grep -A 5 '"audit_plan_ref"' "$instruction_file" | grep -o '"plan_hash": *"[^"]*"' | head -1 | sed 's/"plan_hash": *"\(.*\)"/\1/' || echo "")
    
    if [[ -n "$locked_hash" && -n "$instruction_hash" ]]; then
      if [[ "$instruction_hash" == "$locked_hash" ]]; then
        echo -e "${GREEN}✓ plan_hash matches locked hash${NC}"
      else
        echo -e "${RED}✗ plan_hash mismatch${NC}"
        echo "  Locked:      $locked_hash"
        echo "  Instruction: $instruction_hash"
        ((errors++))
      fi
    fi
  fi
  
  # NEW: Compare verifier mandate coverage against evidence changed_files
  if [[ -n "$EVIDENCE_FILE" && -f "$EVIDENCE_FILE" ]]; then
    # Extract changed files from evidence
    local evidence_files=$(grep -A 50 '"changed_files"' "$EVIDENCE_FILE" 2>/dev/null | grep -o '"[^"]*\.[a-z]\+"' | tr -d '"' | sort)
    
    # Extract plan items to audit from instruction
    local instruction_items=$(grep -A 20 '"plan_item_ids_to_audit"' "$instruction_file" 2>/dev/null | grep -o '"[A-Z]-[0-9]\+"' | tr -d '"' | sort)
    
    # Extract plan items from evidence
    local evidence_items=$(grep -A 20 '"plan_item_ids"' "$EVIDENCE_FILE" 2>/dev/null | grep -o '"[A-Z]-[0-9]\+"' | tr -d '"' | sort)
    
    if [[ -n "$evidence_files" && -n "$instruction_items" ]]; then
      # Check if all evidence plan items are covered by instruction mandate
      local missing_items=""
      while IFS= read -r item; do
        if [[ -n "$item" ]] && ! echo "$instruction_items" | grep -qx "$item"; then
          missing_items+="$item "
        fi
      done <<< "$evidence_items"
      
      if [[ -n "$missing_items" ]]; then
        echo -e "${RED}✗ required plan item missing from audit scope: $missing_items${NC}"
        echo -e "${RED}  (incomplete file coverage - changed files not reviewed)${NC}"
        ((errors++))
      else
        echo -e "${GREEN}✓ Verifier mandate covers all evidence plan items${NC}"
      fi
    fi
  fi

  echo "=========================================="
  
  if [[ $errors -eq 0 ]]; then
    echo -e "${GREEN}✓ Instruction mandate check PASSED${NC}"
    return 0
  else
    echo -e "${RED}✗ Instruction mandate check FAILED with $errors errors${NC}"
    return 1
  fi
}

# Check verdict mandate
check_verdict_mandate() {
  local verdict_file="$1"
  local plan_file="$2"
  local plan_lock_file="$3"
  local check_zero_finding="$4"
  local anomaly_ledger_file="$5"
  local errors=0
  local warnings=0

  echo "Checking Verdict Mandate: $verdict_file"
  echo "=========================================="

  if [[ ! -f "$verdict_file" ]]; then
    echo -e "${RED}✗ Verdict file not found: $verdict_file${NC}"
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    echo -e "${RED}✗ jq is required but not installed${NC}"
    return 1
  fi

  # Check if verdict has audit_plan_ref
  if ! grep -q '"audit_plan_ref"' "$verdict_file"; then
    echo -e "${RED}✗ Verdict missing audit_plan_ref${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ Verdict has audit_plan_ref${NC}"
  fi

  # Check if verdict has plan_item_ids_checked
  if ! grep -q '"plan_item_ids_checked"' "$verdict_file"; then
    echo -e "${RED}✗ Verdict missing plan_item_ids_checked${NC}"
    ((errors++))
  else
    local item_count=$(grep -A 20 '"plan_item_ids_checked"' "$verdict_file" | grep -o '"[A-Z]-[0-9]\+"' | wc -l | tr -d ' ')
    if [[ "$item_count" == "0" ]]; then
      echo -e "${RED}✗ plan_item_ids_checked is empty${NC}"
      ((errors++))
    else
      echo -e "${GREEN}✓ plan_item_ids_checked has $item_count items${NC}"
    fi
  fi

  # Check if verdict has review_trail
  if ! grep -q '"review_trail"' "$verdict_file"; then
    echo -e "${YELLOW}⚠ Verdict missing review_trail${NC}"
    ((warnings++))
  else
    echo -e "${GREEN}✓ Verdict has review_trail${NC}"
  fi

  # Check verdict status — 优先 canonical status 字段，兼容 fallback verdict
  local verdict_value=$(jq -r '(.status // .verdict // "")' "$verdict_file" 2>/dev/null || echo "")
  
  # Check zero-finding justification if verdict is PASS
  if [[ "$check_zero_finding" == true && "$verdict_value" == "PASS" ]]; then
    echo ""
    echo "Checking Zero-Finding Justification..."
    echo "----------------------------------------"
    
    if ! jq -e '.zero_finding_justification' "$verdict_file" >/dev/null 2>&1; then
      echo -e "${RED}✗ Verdict is PASS but missing zero_finding_justification${NC}"
      ((errors++))
    else
      echo -e "${GREEN}✓ Verdict has zero_finding_justification${NC}"
      
      # Check required fields in zero_finding_justification
      local zf_errors=0
      
      local checked_files=$(jq -r '.zero_finding_justification.checked_files // [] | length' "$verdict_file" 2>/dev/null || echo 0)
      local checked_logs=$(jq -r '.zero_finding_justification.checked_command_logs // [] | length' "$verdict_file" 2>/dev/null || echo 0)
      local checked_tests=$(jq -r '.zero_finding_justification.checked_tests // [] | length' "$verdict_file" 2>/dev/null || echo 0)
      local checked_anomalies=$(jq -r '.zero_finding_justification.checked_anomalies // [] | length' "$verdict_file" 2>/dev/null || echo 0)
      
      # ZF009: Check for evidence anchors - at least one must be non-empty
      local total_anchors=$((checked_files + checked_logs + checked_tests))
      if [[ $total_anchors -eq 0 ]]; then
        echo -e "${RED}✗ Zero-finding lacks evidence anchor: checked_files, checked_command_logs, and checked_tests are all empty${NC}"
        echo -e "${RED}  Evidence anchor required: must reference specific files/logs/tests reviewed${NC}"
        ((zf_errors++))
      else
        echo -e "${GREEN}✓ Zero-finding has evidence anchors ($total_anchors references)${NC}"
      fi
      
      # ZF002: Check timeout review - if anomaly ledger has timeout, must be in checked_anomalies
      if [[ -n "$anomaly_ledger_file" && -f "$anomaly_ledger_file" ]]; then
        local timeout_count=$(jq -r '[.entries[] | select(.anomaly_type | test("timeout"))] | length' "$anomaly_ledger_file" 2>/dev/null || echo 0)
        
        if [[ $timeout_count -gt 0 ]]; then
          if [[ $checked_anomalies -eq 0 ]]; then
            echo -e "${RED}✗ Anomaly ledger has $timeout_count timeout entries, but checked_anomalies is empty${NC}"
            echo -e "${RED}  Timeout review required: must review and document timeout anomalies${NC}"
            ((zf_errors++))
          else
            echo -e "${GREEN}✓ Timeout anomalies reviewed (checked_anomalies has $checked_anomalies entries)${NC}"
          fi
        fi
      fi
      
      # Check why_no_p0 and why_no_p1 fields
      local why_no_p0=$(jq -r '.zero_finding_justification.why_no_p0 // ""' "$verdict_file" 2>/dev/null || echo "")
      local why_no_p1=$(jq -r '.zero_finding_justification.why_no_p1 // ""' "$verdict_file" 2>/dev/null || echo "")
      
      if [[ -z "$why_no_p0" ]]; then
        echo -e "${RED}✗ zero_finding_justification missing why_no_p0${NC}"
        ((zf_errors++))
      elif [[ ${#why_no_p0} -lt 10 ]]; then
        echo -e "${YELLOW}⚠ why_no_p0 is too brief (${#why_no_p0} chars, expect detailed explanation)${NC}"
        ((warnings++))
      else
        echo -e "${GREEN}✓ why_no_p0 provided (${#why_no_p0} chars)${NC}"
      fi
      
      if [[ -z "$why_no_p1" ]]; then
        echo -e "${RED}✗ zero_finding_justification missing why_no_p1${NC}"
        ((zf_errors++))
      elif [[ ${#why_no_p1} -lt 10 ]]; then
        echo -e "${YELLOW}⚠ why_no_p1 is too brief (${#why_no_p1} chars, expect detailed explanation)${NC}"
        ((warnings++))
      else
        echo -e "${GREEN}✓ why_no_p1 provided (${#why_no_p1} chars)${NC}"
      fi
      
      # Check for vague justifications (upgraded to error)
      if echo "$why_no_p0" | grep -qiE "all good|looks fine|no issues|everything okay"; then
        echo -e "${RED}✗ why_no_p0 contains vague language, need specific evidence references${NC}"
        ((zf_errors++))
      fi
      
      if echo "$why_no_p1" | grep -qiE "all good|looks fine|no issues|everything okay"; then
        echo -e "${RED}✗ why_no_p1 contains vague language, need specific evidence references${NC}"
        ((zf_errors++))
      fi
      
      errors=$((errors + zf_errors))
    fi
  fi

  echo "=========================================="
  
  if [[ $errors -eq 0 ]]; then
    if [[ $warnings -eq 0 ]]; then
      echo -e "${GREEN}✓ Verdict mandate check PASSED${NC}"
    else
      echo -e "${GREEN}✓ Verdict mandate check PASSED with $warnings warnings${NC}"
    fi
    return 0
  else
    echo -e "${RED}✗ Verdict mandate check FAILED with $errors errors, $warnings warnings${NC}"
    return 1
  fi
}

# Main execution
main() {
  local exit_code=0

  if [[ -n "$INSTRUCTION_FILE" ]]; then
    check_instruction_mandate "$INSTRUCTION_FILE" "$PLAN_FILE" "$PLAN_LOCK_FILE" || exit_code=$?
  fi

  if [[ -n "$VERDICT_FILE" ]]; then
    check_verdict_mandate "$VERDICT_FILE" "$PLAN_FILE" "$PLAN_LOCK_FILE" "$CHECK_ZERO_FINDING" "$ANOMALY_LEDGER_FILE" || exit_code=$?
  fi

  exit $exit_code
}

main
