#!/usr/bin/env bash
# hmte-validate-phases.sh — Validate phases.json against canonical schema
# Version: 1.8.0 (P0-1 fix: fail-closed with all(...) semantics)

set -euo pipefail

PHASES_FILE="${1:-.phase_control/phases.json}"

if [ ! -f "$PHASES_FILE" ]; then
    echo "ERROR: phases.json not found: $PHASES_FILE"
    exit 1
fi

echo "Validating: $PHASES_FILE"

# Check for deprecated field names (ALL phases must not have deprecated fields in release mode)
echo "Checking for deprecated field names..."
if jq -e '.phases[] | select(has("id") or has("name") or has("objective") or has("description"))' "$PHASES_FILE" > /dev/null 2>&1; then
    if [ "${HMTE_LINT_MODE:-}" = "release" ]; then
        echo "FAIL: Found deprecated field names (release mode)"
        echo "Use: phase_id (not id/name), goal (not objective/description)"
        exit 1
    else
        echo "WARN: Found deprecated field names (use phase_id/goal in new files)"
        echo "  Deprecated: id/name/objective/description"
        echo "  Canonical: phase_id/goal"
        # Exit 0 in default mode (WARN only)
    fi
fi

# Validate required top-level fields
echo "Validating schema structure..."
if ! jq -e '(.project_name and (.phases | type == "array") and (.phases | length > 0))' "$PHASES_FILE" > /dev/null 2>&1; then
    echo "FAIL: Missing or invalid top-level fields (project_name / phases array)"
    exit 1
fi

# Check ALL phases have required fields (canonical or legacy aliases)
# Canonical: phase_id, goal, acceptance_criteria
# Legacy aliases: id/name for phase_id, objective/description for goal
# CRITICAL: Use all(...) to ensure EVERY phase passes, not just one
echo "Validating required fields in ALL phases..."
if ! jq -e 'all(.phases[]; ((.phase_id or .id or .name) and (.goal or .objective or .description) and .acceptance_criteria))' "$PHASES_FILE" > /dev/null 2>&1; then
    echo "FAIL: At least one phase missing required fields"
    echo "  Required: phase_id (or id/name), goal (or objective/description), acceptance_criteria"
    exit 1
fi

# Validate acceptance_criteria is array in ALL phases
echo "Validating acceptance_criteria is array in ALL phases..."
if ! jq -e 'all(.phases[]; (.acceptance_criteria | type == "array"))' "$PHASES_FILE" > /dev/null 2>&1; then
    echo "FAIL: At least one phase has acceptance_criteria that is not an array"
    exit 1
fi

# Validate execution_mode if present (ALL phases with execution_mode must be valid)
echo "Validating execution_mode in phases that have it..."
if jq -e '.phases[] | select(has("execution_mode"))' "$PHASES_FILE" > /dev/null 2>&1; then
    if ! jq -e 'all(.phases[] | select(has("execution_mode")); (.execution_mode == "sequential" or .execution_mode == "parallel_safe"))' "$PHASES_FILE" > /dev/null 2>&1; then
        echo "FAIL: At least one phase has invalid execution_mode (must be 'sequential' or 'parallel_safe')"
        exit 1
    fi
fi

# Validate parallel_safe parallel_workers if present (ALL parallel_safe phases must have valid workers)
echo "Validating parallel_safe phases..."
if jq -e '.phases[] | select(.execution_mode == "parallel_safe")' "$PHASES_FILE" > /dev/null 2>&1; then
    # Check ALL parallel_safe phases have parallel_workers
    if ! jq -e 'all(.phases[] | select(.execution_mode == "parallel_safe"); has("parallel_workers"))' "$PHASES_FILE" > /dev/null 2>&1; then
        echo "FAIL: At least one parallel_safe phase missing parallel_workers array"
        exit 1
    fi
    
    # Check ALL parallel_workers have required fields
    if ! jq -e 'all(.phases[] | select(.execution_mode == "parallel_safe") | .parallel_workers[]; (.worker_id and .scope and .forbidden_paths))' "$PHASES_FILE" > /dev/null 2>&1; then
        echo "FAIL: At least one parallel_worker missing required fields (worker_id / scope / forbidden_paths)"
        exit 1
    fi
fi

echo "PASS: phases.json schema valid (all phases validated)"
exit 0
