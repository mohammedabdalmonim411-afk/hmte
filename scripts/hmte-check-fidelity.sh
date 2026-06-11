#!/usr/bin/env bash
# hmte-check-fidelity.sh - Plan-to-Delegation Fidelity checker
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

Check Plan-to-Delegation Fidelity for Worker instructions and evidence.

OPTIONS:
  --instruction PATH       Path to Worker instruction JSON
  --evidence PATH          Path to Worker evidence JSON
  --plan PATH              Path to plan markdown file (required)
  --plan-lock PATH         Path to plan_lock.json (default: .phase_control/plan_lock.json)
  --help                   Show this help message

EXAMPLES:
  # Check Worker instruction
  $(basename "$0") --instruction .phase_control/instructions/phase_1.json \\
    --plan HTE_v2.0_PROJECT_PLAN.md

  # Check Worker evidence
  $(basename "$0") --evidence .phase_control/evidence/phase_1_attempt_1.json \\
    --plan HTE_v2.0_PROJECT_PLAN.md

EXIT CODES:
  0 - Success
  1 - Fidelity check failed
  2 - Invalid arguments
EOF
}

# Parse arguments
INSTRUCTION_FILE=""
EVIDENCE_FILE=""
PLAN_FILE=""
PLAN_LOCK_FILE=".phase_control/plan_lock.json"

while [[ $# -gt 0 ]]; do
  case $1 in
    --instruction)
      INSTRUCTION_FILE="$2"
      shift 2
      ;;
    --evidence)
      EVIDENCE_FILE="$2"
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

if [[ -z "$INSTRUCTION_FILE" && -z "$EVIDENCE_FILE" ]]; then
  echo -e "${RED}Error: Either --instruction or --evidence is required${NC}" >&2
  usage
  exit 2
fi

# Check instruction fidelity
check_instruction_fidelity() {
  local instruction_file="$1"
  local plan_file="$2"
  local plan_lock_file="$3"
  local errors=0

  echo "Checking Instruction Fidelity: $instruction_file"
  echo "=========================================="

  if [[ ! -f "$instruction_file" ]]; then
    echo -e "${RED}✗ Instruction file not found: $instruction_file${NC}"
    return 1
  fi

  # Check if instruction has plan_ref
  if ! grep -q '"plan_ref"' "$instruction_file"; then
    echo -e "${RED}✗ Instruction missing plan_ref${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ Instruction has plan_ref${NC}"
  fi

  # Check if plan_ref has plan_hash
  if ! grep -q '"plan_hash"' "$instruction_file"; then
    echo -e "${RED}✗ plan_ref missing plan_hash${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ plan_ref has plan_hash${NC}"
  fi

  # Check if plan_ref has plan_item_ids
  if ! grep -q '"plan_item_ids"' "$instruction_file"; then
    echo -e "${RED}✗ plan_ref missing plan_item_ids${NC}"
    ((errors++))
  else
    # Extract plan_item_ids array and count items
    local item_count=$(grep -A 20 '"plan_item_ids"' "$instruction_file" | grep -o '"[A-Z]-[0-9]\+"' | wc -l | tr -d ' ')
    if [[ "$item_count" == "0" ]]; then
      echo -e "${RED}✗ plan_item_ids is empty${NC}"
      ((errors++))
    else
      echo -e "${GREEN}✓ plan_item_ids has $item_count items${NC}"
    fi
  fi

  # Check if plan_hash matches locked hash
  if [[ -f "$plan_lock_file" ]]; then
    local locked_hash=$(grep -o '"plan_hash": *"[^"]*"' "$plan_lock_file" | sed 's/"plan_hash": *"\(.*\)"/\1/' || echo "")
    local instruction_hash=$(grep -o '"plan_hash": *"[^"]*"' "$instruction_file" | head -1 | sed 's/"plan_hash": *"\(.*\)"/\1/' || echo "")
    
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
  else
    echo -e "${YELLOW}⚠ No plan_lock.json found - cannot verify plan_hash${NC}"
  fi

  echo "=========================================="
  
  if [[ $errors -eq 0 ]]; then
    echo -e "${GREEN}✓ Instruction fidelity check PASSED${NC}"
    return 0
  else
    echo -e "${RED}✗ Instruction fidelity check FAILED with $errors errors${NC}"
    return 1
  fi
}

# Check evidence fidelity
check_evidence_fidelity() {
  local evidence_file="$1"
  local plan_file="$2"
  local plan_lock_file="$3"
  local errors=0
  local warnings=0

  echo "Checking Evidence Fidelity: $evidence_file"
  echo "=========================================="

  if [[ ! -f "$evidence_file" ]]; then
    echo -e "${RED}✗ Evidence file not found: $evidence_file${NC}"
    return 1
  fi

  # Check if evidence has plan_ref
  if ! grep -q '"plan_ref"' "$evidence_file"; then
    echo -e "${RED}✗ Evidence missing plan_ref${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ Evidence has plan_ref${NC}"
  fi

  # Check if plan_ref has plan_item_ids
  if ! grep -q '"plan_item_ids"' "$evidence_file"; then
    echo -e "${RED}✗ plan_ref missing plan_item_ids${NC}"
    ((errors++))
  else
    local item_count=$(grep -A 20 '"plan_item_ids"' "$evidence_file" | grep -o '"[A-Z]-[0-9]\+"' | wc -l | tr -d ' ')
    if [[ "$item_count" == "0" ]]; then
      echo -e "${RED}✗ plan_item_ids is empty${NC}"
      ((errors++))
    else
      echo -e "${GREEN}✓ plan_item_ids has $item_count items${NC}"
    fi
  fi

  # NEW: Compare evidence plan_item_ids against instruction required items (if instruction exists)
  if [[ -n "$INSTRUCTION_FILE" && -f "$INSTRUCTION_FILE" ]]; then
    # Extract required plan items from instruction
    local instruction_items=$(grep -A 20 '"plan_item_ids"' "$INSTRUCTION_FILE" 2>/dev/null | grep -o '"[A-Z]-[0-9]\+"' | tr -d '"' | sort)
    local evidence_items=$(grep -A 20 '"plan_item_ids"' "$evidence_file" 2>/dev/null | grep -o '"[A-Z]-[0-9]\+"' | tr -d '"' | sort)
    
    if [[ -n "$instruction_items" ]]; then
      local missing_items=""
      while IFS= read -r item; do
        if ! echo "$evidence_items" | grep -qx "$item"; then
          missing_items+="$item "
        fi
      done <<< "$instruction_items"
      
      if [[ -n "$missing_items" ]]; then
        echo -e "${RED}✗ Evidence missing required plan items: $missing_items${NC}"
        ((errors++))
      else
        echo -e "${GREEN}✓ Evidence covers all instruction plan items${NC}"
      fi
    fi
    
    # NEW: Compare required_tests against tests_run
    if grep -q '"required_tests"' "$INSTRUCTION_FILE"; then
      local required_tests=$(grep -A 20 '"required_tests"' "$INSTRUCTION_FILE" 2>/dev/null | grep -o '"[^"]\+_test[^"]*"' | tr -d '"' | sort)
      local tests_run=$(grep -A 20 '"tests_run"' "$evidence_file" 2>/dev/null | grep -o '"[^"]\+"' | tr -d '"' | grep -v 'tests_run' | sort)
      
      if [[ -n "$required_tests" ]]; then
        local missing_tests=""
        while IFS= read -r test; do
          if ! echo "$tests_run" | grep -qx "$test"; then
            missing_tests+="$test "
          fi
        done <<< "$required_tests"
        
        if [[ -n "$missing_tests" ]]; then
          echo -e "${RED}✗ Evidence missing required tests: $missing_tests${NC}"
          ((errors++))
        else
          echo -e "${GREEN}✓ Evidence ran all required tests${NC}"
        fi
      fi
    fi
  fi

  # NEW: Check for skipped tests and validate amendments
  if grep -q '"tests_skipped"' "$evidence_file"; then
    local skipped_tests=$(grep -A 10 '"tests_skipped"' "$evidence_file" | grep -o '"[^"]\+"' | grep -v 'tests_skipped' | tr -d '"')
    if [[ -n "$skipped_tests" ]]; then
      echo -e "${YELLOW}⚠ Found skipped tests${NC}"
      
      # Check for amendments directory
      local evidence_dir=$(dirname "$evidence_file")
      local amendments_dir="$evidence_dir/amendments"
      
      if [[ ! -d "$amendments_dir" ]] && [[ ! -d "amendments" ]]; then
        echo -e "${RED}✗ Tests skipped but no amendments/ directory found${NC}"
        ((errors++))
      else
        echo -e "${GREEN}✓ amendments/ directory exists${NC}"
      fi
    fi
  fi

  # Check if evidence has evidence_by_plan_item (item-level anchoring)
  # Changed from warning to error - item-level anchoring is required for v2.0
  if ! grep -q '"evidence_by_plan_item"' "$evidence_file"; then
    echo -e "${RED}✗ Evidence missing evidence_by_plan_item (item-level anchoring required)${NC}"
    ((errors++))
  else
    echo -e "${GREEN}✓ Evidence has evidence_by_plan_item${NC}"
  fi

  # Check if evidence has tests_run
  if ! grep -q '"tests_run"' "$evidence_file"; then
    echo -e "${YELLOW}⚠ Evidence missing tests_run${NC}"
    ((warnings++))
  else
    echo -e "${GREEN}✓ Evidence has tests_run${NC}"
  fi

  if ! grep -q '"changed_files"' "$evidence_file"; then
    echo -e "${YELLOW}⚠ Evidence missing changed_files${NC}"
    ((warnings++))
  else
    local files_count=$(grep -o '"changed_files"[^]]*]' "$evidence_file" | grep -o '"[^"]\+\.[a-z]\+"' | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ Evidence has changed_files ($files_count files)${NC}"
  fi

  # NEW: Check for required artifacts in plan
  if [[ -f "$plan_file" ]]; then
    # Look for Required Artifacts section in plan
    if grep -q "## Required Artifacts" "$plan_file"; then
      local required_artifacts=$(sed -n '/## Required Artifacts/,/^##/p' "$plan_file" | grep -o 'ART-[0-9]\+' || echo "")
      if [[ -n "$required_artifacts" ]]; then
        # Check if evidence mentions these artifacts
        local missing_artifacts=""
        while IFS= read -r artifact; do
          if [[ -n "$artifact" ]] && ! grep -q "$artifact" "$evidence_file"; then
            missing_artifacts+="$artifact "
          fi
        done <<< "$required_artifacts"
        
        if [[ -n "$missing_artifacts" ]]; then
          echo -e "${RED}✗ Evidence missing required artifacts: $missing_artifacts${NC}"
          ((errors++))
        fi
      fi
    fi
  fi

  # NEW: Check for invalid plan items (not in plan)
  if [[ -f "$plan_file" ]]; then
    local plan_item_ids=$(grep -o '[A-Z]-[0-9]\+' "$plan_file" | sort -u)
    local evidence_items=$(grep -A 20 '"plan_item_ids"' "$evidence_file" 2>/dev/null | grep -o '"[A-Z]-[0-9]\+"' | tr -d '"')
    
    local invalid_items=""
    while IFS= read -r item; do
      if [[ -n "$item" ]] && ! echo "$plan_item_ids" | grep -qx "$item"; then
        invalid_items+="$item "
      fi
    done <<< "$evidence_items"
    
    if [[ -n "$invalid_items" ]]; then
      echo -e "${RED}✗ Evidence references plan items not in plan (required test dropped): $invalid_items${NC}"
      ((errors++))
    fi
    
    # NEW: Check if evidence covers all P0 plan items
    local p0_items=$(sed -n '/## Scope/,/^##/p' "$plan_file" | grep '| P0 |' | grep -o '[A-Z]-[0-9]\+' || echo "")
    if [[ -n "$p0_items" ]]; then
      local missing_p0=""
      while IFS= read -r item; do
        if [[ -n "$item" ]] && ! echo "$evidence_items" | grep -qx "$item"; then
          missing_p0+="$item "
        fi
      done <<< "$p0_items"
      
      if [[ -n "$missing_p0" ]]; then
        echo -e "${RED}✗ Evidence missing required P0 plan items: $missing_p0${NC}"
        ((errors++))
      else
        local p0_count=$(echo "$p0_items" | wc -w | tr -d ' ')
        echo -e "${GREEN}✓ Evidence covers all $p0_count P0 plan items${NC}"
      fi
    fi
    
    # NEW: Check for partial implementation patterns (A, B, C in descriptions)
    while IFS= read -r item; do
      if [[ -n "$item" ]]; then
        # Get the description for this plan item
        local item_line=$(grep "$item" "$plan_file" | head -1)
        # Check if description contains multiple components like "A, B, C" or "with A, B, C"
        if echo "$item_line" | grep -qE "(with|Implement|Complete).*[A-Z],.*[A-Z]"; then
          # This is a multi-component item, check if evidence has required_steps
          if ! grep -q '"required_steps"' "$evidence_file" && ! grep -q '"completed_steps"' "$evidence_file"; then
            # Check if this is a P0 item
            if echo "$item_line" | grep -q '| P0 |'; then
              echo -e "${RED}✗ plan item $item incomplete: partial implementation detected (incomplete steps)${NC}"
              ((errors++))
            else
              echo -e "${YELLOW}⚠ Plan item $item has multiple components but evidence lacks step tracking${NC}"
              ((warnings++))
            fi
          fi
        fi
      fi
    done <<< "$evidence_items"
  fi

  # Check if plan_hash matches locked hash
  if [[ -f "$plan_lock_file" ]]; then
    local locked_hash=$(grep -o '"plan_hash": *"[^"]*"' "$plan_lock_file" | sed 's/"plan_hash": *"\(.*\)"/\1/' || echo "")
    local evidence_hash=$(grep -o '"plan_hash": *"[^"]*"' "$evidence_file" | head -1 | sed 's/"plan_hash": *"\(.*\)"/\1/' || echo "")
    
    if [[ -n "$locked_hash" && -n "$evidence_hash" ]]; then
      if [[ "$evidence_hash" == "$locked_hash" ]]; then
        echo -e "${GREEN}✓ plan_hash matches locked hash${NC}"
      else
        echo -e "${RED}✗ plan_hash mismatch${NC}"
        echo "  Locked:   $locked_hash"
        echo "  Evidence: $evidence_hash"
        ((errors++))
      fi
    fi
  fi

  echo "=========================================="
  
  if [[ $errors -eq 0 ]]; then
    if [[ $warnings -eq 0 ]]; then
      echo -e "${GREEN}✓ Evidence fidelity check PASSED${NC}"
    else
      echo -e "${GREEN}✓ Evidence fidelity check PASSED with $warnings warnings${NC}"
    fi
    return 0
  else
    echo -e "${RED}✗ Evidence fidelity check FAILED with $errors errors, $warnings warnings${NC}"
    return 1
  fi
}

# Main execution
main() {
  local exit_code=0

  if [[ -n "$INSTRUCTION_FILE" ]]; then
    check_instruction_fidelity "$INSTRUCTION_FILE" "$PLAN_FILE" "$PLAN_LOCK_FILE" || exit_code=$?
  fi

  if [[ -n "$EVIDENCE_FILE" ]]; then
    check_evidence_fidelity "$EVIDENCE_FILE" "$PLAN_FILE" "$PLAN_LOCK_FILE" || exit_code=$?
  fi

  exit $exit_code
}

main
