#!/usr/bin/env bash
set -uo pipefail

# TAF Rule-first Workflow Intensity Selector v2.0
# Rule-first, AI advisory optional

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Rule-first Workflow Intensity Selector for TriAgentFlow / TAF v2.0.

OPTIONS:
  --task-description TEXT  Task description (required)
  --changed-files FILES    Comma-separated list of changed files
  --plan PATH              Path to plan markdown file (optional)
  --with-ai                Enable AI advisory mode (optional)
  --output PATH            Output JSON path (default: intensity-recommendation.json)
  --help                   Show this help message

INTENSITY LEVELS:
  direct              Typo, comments, non-core docs only
  standard            Default for most tasks
  strict              Core protocol, schema, gate files
  parallel_safe       Phase-internal parallelism
  release             Release preparation
  dogfood             Full dogfood validation

EXAMPLES:
  # Recommend intensity for a task
  $0 --task-description "Fix typo in README" --changed-files "README.md"

  # With AI advisory mode
  $0 --task-description "Modify phase_gate.sh" --changed-files "scripts/phase_gate.sh" --with-ai
EOF
  exit 0
}

log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo "ℹ $1"; }

# Parse arguments
TASK_DESC=""
CHANGED_FILES=""
PLAN_PATH=""
WITH_AI=false
OUTPUT="intensity-recommendation.json"

while [[ $# -gt 0 ]]; do
  case $1 in
    --task-description) TASK_DESC="$2"; shift 2 ;;
    --changed-files) CHANGED_FILES="$2"; shift 2 ;;
    --plan) PLAN_PATH="$2"; shift 2 ;;
    --with-ai) WITH_AI=true; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

if [[ -z "$TASK_DESC" ]]; then
  echo "Error: --task-description is required"
  exit 1
fi

echo "=========================================="
echo "TAF Rule-first Workflow Selector v2.0"
echo "=========================================="
echo "Task: $TASK_DESC"
echo "Changed Files: ${CHANGED_FILES:-none}"
echo "AI Advisory: $WITH_AI"
echo ""

# Rule-based intensity selection
RECOMMENDED_INTENSITY="standard"
REASON="Default intensity for most tasks"
CONFIDENCE="medium"

# Rule 1: Core protocol files → strict
if echo "$CHANGED_FILES" | grep -qE "phase_gate\.sh|hmte-final-check\.sh|HTE_PROTOCOL\.md"; then
  RECOMMENDED_INTENSITY="strict"
  REASON="Core protocol file detected (phase_gate.sh, final-check, or HTE_PROTOCOL.md)"
  CONFIDENCE="high"
  
# Rule 2: Schema files → strict
elif echo "$CHANGED_FILES" | grep -qE "schema\.json|evidence-schema|verdict-schema"; then
  RECOMMENDED_INTENSITY="strict"
  REASON="Schema file modification detected"
  CONFIDENCE="high"
  
# Rule 3: Gate scripts → strict
elif echo "$CHANGED_FILES" | grep -qE "scripts/hmte-.*gate"; then
  RECOMMENDED_INTENSITY="strict"
  REASON="Gate script modification detected"
  CONFIDENCE="high"
  
# Rule 4: Skills → strict
elif echo "$CHANGED_FILES" | grep -qE "src/skills/hmte/"; then
  RECOMMENDED_INTENSITY="strict"
  REASON="TAF legacy hmte skill modification detected"
  CONFIDENCE="high"
  
# Rule 5: TAF legacy hmte scripts → standard
elif echo "$CHANGED_FILES" | grep -qE "scripts/hmte-"; then
  RECOMMENDED_INTENSITY="standard"
  REASON="TAF legacy hmte utility script modification"
  CONFIDENCE="medium"
  
# Rule 6: Source code → standard
elif echo "$CHANGED_FILES" | grep -qE "\.(py|js|sh|ts)$"; then
  RECOMMENDED_INTENSITY="standard"
  REASON="Source code modification"
  CONFIDENCE="medium"
  
# Rule 7: Agents → standard
elif echo "$CHANGED_FILES" | grep -qE "src/agents/"; then
  RECOMMENDED_INTENSITY="standard"
  REASON="Agent definition modification"
  CONFIDENCE="medium"
  
# Rule 8: Documentation only (non-architecture) → direct
elif echo "$CHANGED_FILES" | grep -qE "^(README\.md|CONTRIBUTING\.md|docs/[^/]+\.md)$" && \
     ! echo "$CHANGED_FILES" | grep -qE "(HTE_PROTOCOL|PLAN_CONTRACT|PLAN_LOCK|ARCHITECTURE)"; then
  RECOMMENDED_INTENSITY="direct"
  REASON="Documentation-only change (non-architecture)"
  CONFIDENCE="medium"
  
# Rule 9: Comments/typos keywords in task description → direct
elif echo "$TASK_DESC" | grep -qiE "(typo|comment|formatting|whitespace)"; then
  RECOMMENDED_INTENSITY="direct"
  REASON="Task description indicates typo/comment fix"
  CONFIDENCE="low"
fi

# Check forbidden direct patterns
DIRECT_FORBIDDEN=false
if [[ "$RECOMMENDED_INTENSITY" == "direct" ]]; then
  if echo "$CHANGED_FILES" | grep -qE "(scripts/|src/|\.py$|\.js$|\.sh$)"; then
    DIRECT_FORBIDDEN=true
    RECOMMENDED_INTENSITY="standard"
    REASON="Direct mode forbidden for code/scripts (upgrading to standard)"
    CONFIDENCE="high"
  fi
fi

log_info "Rule-based recommendation:"
log_pass "Intensity: $RECOMMENDED_INTENSITY"
log_info "Reason: $REASON"
log_info "Confidence: $CONFIDENCE"

# AI Advisory Mode (optional)
AI_RECOMMENDATION=""
AI_CONFIDENCE=""
AI_REASONING=""

if [[ "$WITH_AI" == true ]]; then
  log_info ""
  log_info "AI Advisory Mode enabled (P1 optional feature)"
  log_warn "AI analysis not implemented in v2.0 MVP"
  log_warn "Using rule-based recommendation only"
  AI_RECOMMENDATION="$RECOMMENDED_INTENSITY"
  AI_CONFIDENCE="n/a"
  AI_REASONING="AI advisory not available in MVP"
fi

# Generate output JSON
cat > "$OUTPUT" <<EOF
{
  "task_description": "$TASK_DESC",
  "changed_files": "${CHANGED_FILES}",
  "rule_mode": {
    "recommended_intensity": "$RECOMMENDED_INTENSITY",
    "reason": "$REASON",
    "confidence": "$CONFIDENCE"
  },
  "ai_advisory_mode": {
    "enabled": $WITH_AI,
    "recommendation": "${AI_RECOMMENDATION}",
    "confidence": "${AI_CONFIDENCE}",
    "reasoning": "${AI_REASONING}"
  },
  "final_recommendation": "$RECOMMENDED_INTENSITY"
}
EOF

log_info ""
log_pass "Recommendation saved to: $OUTPUT"
echo ""
echo "Final Recommendation: $RECOMMENDED_INTENSITY"
