#!/usr/bin/env bash
# hmte-recipe-compose.sh - Recipe composition script
# Generates phases.json from recipe + plan items

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
RECIPE=""
PLAN=""
PLAN_ITEMS=""
OUTPUT=""
VERBOSE=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate phases.json from TriAgentFlow / TAF workflow recipe.

OPTIONS:
    --recipe PATH           Recipe markdown file
    --plan PATH             Plan contract file
    --plan-items IDS        Comma-separated plan item IDs
    --output PATH           Output phases.json path
    --verbose               Verbose output
    -h, --help              Show this help

EXAMPLES:
    # Generate phases from recipe
    $(basename "$0") \\
      --recipe docs/recipes/recipe-schema-change.md \\
      --plan HTE_v2.0_PROJECT_PLAN.md \\
      --plan-items "S-001,AC-001,T-001" \\
      --output .phase_control/phases.json

EOF
    exit 0
}

log() {
    if [ "$VERBOSE" = true ]; then
        echo "[hmte-recipe-compose] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --recipe)
            RECIPE="$2"
            shift 2
            ;;
        --plan)
            PLAN="$2"
            shift 2
            ;;
        --plan-items)
            PLAN_ITEMS="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required arguments
[ -z "$RECIPE" ] && error "--recipe required"
[ -z "$PLAN" ] && error "--plan required"
[ -z "$PLAN_ITEMS" ] && error "--plan-items required"
[ -z "$OUTPUT" ] && error "--output required"

[ ! -f "$RECIPE" ] && error "Recipe not found: $RECIPE"
[ ! -f "$PLAN" ] && error "Plan not found: $PLAN"

log "Recipe: $RECIPE"
log "Plan: $PLAN"
log "Plan items: $PLAN_ITEMS"
log "Output: $OUTPUT"

# Extract recipe metadata
log "Extracting recipe metadata..."
RECIPE_VERSION=$(grep -E "^\*\*Version\*\*:" "$RECIPE" | sed 's/.*: //' | tr -d ' ')
RECIPE_DEPRECATED=$(grep -E "^\*\*Deprecated\*\*:" "$RECIPE" | sed 's/.*: //' | tr -d ' ')
RECIPE_RISK=$(grep -E "^\*\*Risk Level\*\*:" "$RECIPE" | sed 's/.*: //' | tr -d ' ')

log "Version: $RECIPE_VERSION"
log "Deprecated: $RECIPE_DEPRECATED"
log "Risk Level: $RECIPE_RISK"

# Check if deprecated
if [ "$RECIPE_DEPRECATED" = "Yes" ]; then
    SUPERSEDED_BY=$(grep -E "^\*\*Superseded by\*\*:" "$RECIPE" | sed 's/.*: //' | tr -d ' ')
    error "Recipe is deprecated. Use $SUPERSEDED_BY instead."
fi

# Extract phases from recipe
log "Extracting phases from recipe..."
PHASE_COUNT=$(grep -E "^### Phase [0-9]+:" "$RECIPE" | wc -l | tr -d ' ')
log "Found $PHASE_COUNT phases in recipe"

# Generate phases.json
log "Generating phases.json..."
cat > "$OUTPUT" << EOF
{
  "recipe": "$(basename "$RECIPE")",
  "recipe_version": "$RECIPE_VERSION",
  "plan": "$(basename "$PLAN")",
  "plan_items": $(echo "$PLAN_ITEMS" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/' | tr -d '\n'),
  "phases": [
EOF

# Extract phase information
PHASE_NUM=1
while [ $PHASE_NUM -le "$PHASE_COUNT" ]; do
    PHASE_TITLE=$(grep -E "^### Phase ${PHASE_NUM}:" "$RECIPE" | sed "s/### Phase ${PHASE_NUM}: //")
    
    # Add comma if not first phase
    if [ $PHASE_NUM -gt 1 ]; then
        echo "," >> "$OUTPUT"
    fi
    
    cat >> "$OUTPUT" << EOF
    {
      "phase_id": "phase_${PHASE_NUM}",
      "title": "$PHASE_TITLE",
      "plan_items": $(echo "$PLAN_ITEMS" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/' | tr -d '\n'),
      "intensity": "$(echo "$RECIPE_RISK" | tr '[:upper:]' '[:lower:]')"
    }
EOF
    
    PHASE_NUM=$((PHASE_NUM + 1))
done

cat >> "$OUTPUT" << EOF

  ]
}
EOF

log "Generated: $OUTPUT"
log "SUCCESS"

# Validate JSON
if command -v python3 &> /dev/null; then
    python3 -m json.tool "$OUTPUT" > /dev/null || error "Invalid JSON generated"
    log "JSON validation: PASS"
fi

echo "Recipe composition complete: $OUTPUT"
exit 0
