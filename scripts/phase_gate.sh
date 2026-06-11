#!/usr/bin/env bash
# TAF phase_gate.sh wrapper
# Locates and calls the actual phase_gate.sh from HMTE skill directory

set -euo pipefail

# Try to locate phase_gate.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_GATE_IMPL=""

# 1. Check if we're in the TAF repo (legacy src/skills/hmte path exists)
if [[ -f "$SCRIPT_DIR/../src/skills/hmte/scripts/phase_gate.sh" ]]; then
  PHASE_GATE_IMPL="$SCRIPT_DIR/../src/skills/hmte/scripts/phase_gate.sh"
# 2. Check HMTE_SKILL_DIR environment variable
elif [[ -n "${HMTE_SKILL_DIR:-}" ]] && [[ -f "$HMTE_SKILL_DIR/scripts/phase_gate.sh" ]]; then
  PHASE_GATE_IMPL="$HMTE_SKILL_DIR/scripts/phase_gate.sh"
# 3. Check ~/.hermes/skills/hmte
elif [[ -f "$HOME/.hermes/skills/hmte/scripts/phase_gate.sh" ]]; then
  PHASE_GATE_IMPL="$HOME/.hermes/skills/hmte/scripts/phase_gate.sh"
else
  echo "ERROR: Cannot locate phase_gate.sh implementation" >&2
  echo "" >&2
  echo "Searched:" >&2
  echo "  1. $SCRIPT_DIR/../src/skills/hmte/scripts/phase_gate.sh" >&2
  echo "  2. \$HMTE_SKILL_DIR/scripts/phase_gate.sh (HMTE_SKILL_DIR=${HMTE_SKILL_DIR:-not set})" >&2
  echo "  3. ~/.hermes/skills/hmte/scripts/phase_gate.sh" >&2
  echo "" >&2
  echo "Solutions:" >&2
  echo "  - Set HMTE_SKILL_DIR to your TAF legacy hmte skill directory" >&2
  echo "  - Run 'bash /path/to/hmte/install-to-hermes.sh' to install the TAF skill" >&2
  exit 1
fi

# Export HMTE_SKILL_DIR for dependencies (hmte-audit-flow.py, parallel_gate_check.py)
if [[ -z "${HMTE_SKILL_DIR:-}" ]]; then
  export HMTE_SKILL_DIR="$(dirname "$PHASE_GATE_IMPL")/.."
fi

# Call the actual implementation
exec bash "$PHASE_GATE_IMPL" "$@"
