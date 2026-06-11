#!/usr/bin/env bash
#
# hmte-plan-lock.sh - Generate and verify plan lock
#
# Usage:
#   hmte-plan-lock.sh --plan <file> --generate --approved-by <name>
#   hmte-plan-lock.sh --plan <file> --verify --lock <lock_file>
#   hmte-plan-lock.sh --plan <file> --amend --reason <text> --approved-by <name>
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PLAN_FILE=""
ACTION=""
APPROVED_BY=""
LOCK_FILE=".phase_control/plan_lock.json"
AMENDMENT_REASON=""
OLD_LOCK_FILE=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --plan)
      PLAN_FILE="$2"
      shift 2
      ;;
    --generate)
      ACTION="generate"
      shift
      ;;
    --verify)
      ACTION="verify"
      shift
      ;;
    --amend)
      ACTION="amend"
      shift
      ;;
    --approved-by)
      APPROVED_BY="$2"
      shift 2
      ;;
    --lock)
      LOCK_FILE="$2"
      shift 2
      ;;
    --reason)
      AMENDMENT_REASON="$2"
      shift 2
      ;;
    --old-lock)
      OLD_LOCK_FILE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: hmte-plan-lock.sh --plan <plan_file> [OPTIONS]"
      echo ""
      echo "Generate, verify, or amend plan lock."
      echo ""
      echo "OPTIONS:"
      echo "    --plan <file>           Plan file path (required)"
      echo "    --generate              Generate new plan lock"
      echo "    --verify                Verify existing plan lock"
      echo "    --amend                 Create amendment"
      echo "    --approved-by <name>    Approver name (required for generate/amend)"
      echo "    --lock <file>           Lock file path (default: .phase_control/plan_lock.json)"
      echo "    --reason <text>         Amendment reason (required for amend, ≥100 chars)"
      echo "    --old-lock <file>       Old lock file (required for amend)"
      echo "    --output <file>         Output path for new lock"
      echo "    --help                  Show this help message"
      echo ""
      echo "EXAMPLES:"
      echo "    # Generate lock"
      echo "    hmte-plan-lock.sh --plan HTE_v2.0_PROJECT_PLAN.md --generate --approved-by maintainer"
      echo ""
      echo "    # Verify lock"
      echo "    hmte-plan-lock.sh --plan HTE_v2.0_PROJECT_PLAN.md --verify --lock .phase_control/plan_lock.json"
      echo ""
      echo "    # Create amendment"
      echo "    hmte-plan-lock.sh --plan HTE_v2.0_PROJECT_PLAN.md --amend \\"
      echo "        --reason \"Detailed reason...\" \\"
      echo "        --approved-by maintainer \\"
      echo "        --old-lock .phase_control/plan_lock.json \\"
      echo "        --output .phase_control/plan_lock_v2.json"
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Unknown option: $1${NC}"
      exit 2
      ;;
  esac
done

# Validate required arguments
if [ -z "$PLAN_FILE" ]; then
  echo -e "${RED}❌ Missing required option: --plan${NC}"
  exit 2
fi

if [ -z "$ACTION" ]; then
  echo -e "${RED}❌ Missing required action: --generate, --verify, or --amend${NC}"
  exit 2
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo -e "${RED}❌ Plan file not found: $PLAN_FILE${NC}"
  exit 1
fi

# Function: Generate plan hash
generate_plan_hash() {
  local plan_file="$1"
  local hash=$(sha256sum "$plan_file" | awk '{print $1}')
  echo "sha256:${hash}"
}

# Function: Extract plan ID from plan file
extract_plan_id() {
  local plan_file="$1"
  local plan_id=$(grep -m 1 '^\*\*Plan ID\*\*:' "$plan_file" | sed 's/.*: //' | tr -d ' ')
  if [ -z "$plan_id" ]; then
    echo -e "${RED}❌ Could not extract Plan ID from $plan_file${NC}" >&2
    exit 1
  fi
  echo "$plan_id"
}

# Function: Extract scope version from plan file
extract_scope_version() {
  local plan_file="$1"
  local version=$(grep -m 1 '^\*\*Version\*\*:' "$plan_file" | sed 's/.*: //' | tr -d ' ')
  if [ -z "$version" ]; then
    version="1.0"
  fi
  echo "$version"
}

# Action: Generate lock
if [ "$ACTION" = "generate" ]; then
  if [ -z "$APPROVED_BY" ]; then
    echo -e "${RED}❌ Missing required option: --approved-by${NC}"
    exit 2
  fi

  echo "Generating Plan Lock..."
  echo "═══════════════════════════════════════════════════════════"

  # Extract plan ID and version
  PLAN_ID=$(extract_plan_id "$PLAN_FILE")
  SCOPE_VERSION=$(extract_scope_version "$PLAN_FILE")
  
  # Generate hash
  PLAN_HASH=$(generate_plan_hash "$PLAN_FILE")
  
  # Generate timestamp
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Determine output file
  if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$LOCK_FILE"
  fi
  
  # Create directory if needed
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  
  # Generate lock JSON
  cat > "$OUTPUT_FILE" <<EOF
{
  "plan_id": "$PLAN_ID",
  "plan_path": "$PLAN_FILE",
  "plan_hash": "$PLAN_HASH",
  "approved_by": "$APPROVED_BY",
  "approved_at": "$TIMESTAMP",
  "scope_version": "$SCOPE_VERSION",
  "amendment_policy": {
    "requires_approval": true,
    "min_reason_length": 100,
    "allowed_amenders": ["human"]
  },
  "locked_at": "$TIMESTAMP"
}
EOF

  echo -e "${GREEN}✅ Plan locked${NC}"
  echo "   Plan ID:      $PLAN_ID"
  echo "   Plan Hash:    $PLAN_HASH"
  echo "   Approved By:  $APPROVED_BY"
  echo "   Locked At:    $TIMESTAMP"
  echo "   Lock File:    $OUTPUT_FILE"
  exit 0
fi

# Action: Verify lock
if [ "$ACTION" = "verify" ]; then
  echo "Verifying Plan Lock..."
  echo "═══════════════════════════════════════════════════════════"

  if [ ! -f "$LOCK_FILE" ]; then
    echo -e "${RED}❌ Lock file not found: $LOCK_FILE${NC}"
    echo "   Plan not locked. Run: bash scripts/hmte-plan-lock.sh --generate"
    exit 1
  fi

  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq is required but not installed${NC}"
    exit 1
  fi

  # Read locked hash
  LOCKED_HASH=$(jq -r '.plan_hash' "$LOCK_FILE" | sed 's/sha256://')
  
  # Calculate current hash
  CURRENT_HASH=$(sha256sum "$PLAN_FILE" | awk '{print $1}')
  
  # Compare
  if [ "$LOCKED_HASH" != "$CURRENT_HASH" ]; then
    echo -e "${RED}❌ Plan hash mismatch!${NC}"
    echo "   Locked:  $LOCKED_HASH"
    echo "   Current: $CURRENT_HASH"
    echo ""
    echo "   Plan modified without amendment."
    echo "   Run: bash scripts/hmte-plan-lock.sh --amend"
    exit 1
  fi
  
  # Read lock metadata
  PLAN_ID=$(jq -r '.plan_id' "$LOCK_FILE")
  APPROVED_BY=$(jq -r '.approved_by' "$LOCK_FILE")
  LOCKED_AT=$(jq -r '.locked_at' "$LOCK_FILE")
  
  echo -e "${GREEN}✅ Plan lock verified${NC}"
  echo "   Plan ID:      $PLAN_ID"
  echo "   Plan Hash:    sha256:$LOCKED_HASH"
  echo "   Approved By:  $APPROVED_BY"
  echo "   Locked At:    $LOCKED_AT"
  exit 0
fi

# Action: Amend
if [ "$ACTION" = "amend" ]; then
  if [ -z "$APPROVED_BY" ]; then
    echo -e "${RED}❌ Missing required option: --approved-by${NC}"
    exit 2
  fi

  if [ -z "$AMENDMENT_REASON" ]; then
    echo -e "${RED}❌ Missing required option: --reason${NC}"
    exit 2
  fi

  if [ -z "$OLD_LOCK_FILE" ]; then
    echo -e "${RED}❌ Missing required option: --old-lock${NC}"
    exit 2
  fi

  if [ ! -f "$OLD_LOCK_FILE" ]; then
    echo -e "${RED}❌ Old lock file not found: $OLD_LOCK_FILE${NC}"
    exit 1
  fi

  # Check reason length
  REASON_LENGTH=${#AMENDMENT_REASON}
  if [ "$REASON_LENGTH" -lt 100 ]; then
    echo -e "${RED}❌ Amendment reason too short: $REASON_LENGTH chars (minimum: 100)${NC}"
    echo "   Provide detailed reason with:"
    echo "   - Change rationale"
    echo "   - Impact scope"
    echo "   - Risk assessment"
    exit 1
  fi

  echo "Creating Amendment..."
  echo "═══════════════════════════════════════════════════════════"

  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq is required but not installed${NC}"
    exit 1
  fi

  # Read old lock
  OLD_HASH=$(jq -r '.plan_hash' "$OLD_LOCK_FILE")
  PLAN_ID=$(jq -r '.plan_id' "$OLD_LOCK_FILE")
  
  # Generate new hash
  NEW_HASH=$(generate_plan_hash "$PLAN_FILE")
  
  # Check if hash actually changed
  if [ "$OLD_HASH" = "$NEW_HASH" ]; then
    echo -e "${YELLOW}⚠️  Plan hash unchanged${NC}"
    echo "   Old Hash: $OLD_HASH"
    echo "   New Hash: $NEW_HASH"
    echo "   No amendment needed."
    exit 0
  fi
  
  # Generate timestamp
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Generate amendment ID
  AMENDMENT_DIR=".phase_control/amendments"
  mkdir -p "$AMENDMENT_DIR"
  
  # Count existing amendments
  AMENDMENT_COUNT=$(ls -1 "$AMENDMENT_DIR" 2>/dev/null | wc -l | tr -d ' ')
  AMENDMENT_ID=$(printf "AMD-%03d" $((AMENDMENT_COUNT + 1)))
  
  # Determine output file
  if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE=".phase_control/plan_lock_v$((AMENDMENT_COUNT + 2)).json"
  fi
  
  # Create amendment record
  AMENDMENT_FILE="$AMENDMENT_DIR/${AMENDMENT_ID}.json"
  cat > "$AMENDMENT_FILE" <<EOF
{
  "amendment_id": "$AMENDMENT_ID",
  "plan_id": "$PLAN_ID",
  "original_hash": "$OLD_HASH",
  "new_hash": "$NEW_HASH",
  "reason": "$AMENDMENT_REASON",
  "approved_by": "$APPROVED_BY",
  "approved_at": "$TIMESTAMP"
}
EOF

  # Extract scope version
  SCOPE_VERSION=$(extract_scope_version "$PLAN_FILE")
  
  # Generate new lock
  cat > "$OUTPUT_FILE" <<EOF
{
  "plan_id": "$PLAN_ID",
  "plan_path": "$PLAN_FILE",
  "plan_hash": "$NEW_HASH",
  "approved_by": "$APPROVED_BY",
  "approved_at": "$TIMESTAMP",
  "scope_version": "$SCOPE_VERSION",
  "amendment_policy": {
    "requires_approval": true,
    "min_reason_length": 100,
    "allowed_amenders": ["human"]
  },
  "locked_at": "$TIMESTAMP",
  "amended_from": "$OLD_HASH",
  "amendment_id": "$AMENDMENT_ID"
}
EOF

  echo -e "${GREEN}✅ Amendment created${NC}"
  echo "   Amendment ID: $AMENDMENT_ID"
  echo "   Old Hash:     $OLD_HASH"
  echo "   New Hash:     $NEW_HASH"
  echo "   Approved By:  $APPROVED_BY"
  echo "   Amendment:    $AMENDMENT_FILE"
  echo "   New Lock:     $OUTPUT_FILE"
  exit 0
fi

# Should not reach here
echo -e "${RED}❌ Invalid action: $ACTION${NC}"
exit 1
