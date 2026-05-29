#!/bin/bash
# Simplified wrapper for write_state.py
# Usage: hmte-write-state.sh <key> <value>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find write_state.py in multiple possible locations
if [ -f "$HOME/.hermes/profiles/default/skills/hmte/scripts/write_state.py" ]; then
    WRITE_STATE="$HOME/.hermes/profiles/default/skills/hmte/scripts/write_state.py"
elif [ -f "$PROJECT_ROOT/src/skills/hmte/scripts/write_state.py" ]; then
    WRITE_STATE="$PROJECT_ROOT/src/skills/hmte/scripts/write_state.py"
elif [ -f "$PROJECT_ROOT/.claude/skills/hmte/scripts/write_state.py" ]; then
    WRITE_STATE="$PROJECT_ROOT/.claude/skills/hmte/scripts/write_state.py"
else
    echo "Error: write_state.py not found in expected locations" >&2
    echo "Searched:" >&2
    echo "  - ~/.hermes/profiles/default/skills/hmte/scripts/write_state.py" >&2
    echo "  - $PROJECT_ROOT/src/skills/hmte/scripts/write_state.py" >&2
    echo "  - $PROJECT_ROOT/.claude/skills/hmte/scripts/write_state.py" >&2
    exit 1
fi

# Execute write_state.py with all arguments
python "$WRITE_STATE" "$@"
