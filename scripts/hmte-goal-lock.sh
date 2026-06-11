#!/bin/bash
# hmte-goal-lock.sh — TAF legacy P0 Goal Lock
# Reads phases.json + session.json, creates goal_lock.json with SHA256 hashes
# of each phase's acceptance_criteria. Creates amendments/ directory.
# Fails if goal_lock.json already exists unless --force.
set -euo pipefail

# ─── Color output ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}INFO${NC}  $*"; }
warn()  { echo -e "${YELLOW}WARN${NC} $*"; }
pass()  { echo -e "${GREEN}PASS${NC} $*"; }
fail()  { echo -e "${RED}FAIL${NC} $*"; }

# ─── Parse args ───────────────────────────────────────────────────
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        *)
            echo "Usage: $0 [--force]" >&2
            exit 1
            ;;
    esac
done

CTRL=".phase_control"
PHASES_FILE="$CTRL/phases.json"
SESSION_FILE="$CTRL/session.json"
GOAL_LOCK_FILE="$CTRL/goal_lock.json"
AMENDMENTS_DIR="$CTRL/amendments"

# ─── Pre-checks ───────────────────────────────────────────────────
if [ ! -f "$PHASES_FILE" ]; then
    fail "phases.json not found at $PHASES_FILE"
    echo "  Create phases.json first (via kickoff + Leader)" >&2
    exit 1
fi

if [ ! -f "$SESSION_FILE" ]; then
    fail "session.json not found at $SESSION_FILE"
    echo "  Run hmte-kickoff.sh first" >&2
    exit 1
fi

if [ -f "$GOAL_LOCK_FILE" ]; then
    if [ "$FORCE" = false ]; then
        fail "goal_lock.json already exists at $GOAL_LOCK_FILE"
        echo "  Use --force to overwrite" >&2
        exit 1
    fi
    warn "Overwriting existing goal_lock.json (--force)"
fi

# ─── Generate goal_lock.json ─────────────────────────────────────
mkdir -p "$AMENDMENTS_DIR"

python3 - "$PHASES_FILE" "$SESSION_FILE" "$GOAL_LOCK_FILE" "$AMENDMENTS_DIR" <<'PY'
import json, hashlib, sys
from datetime import datetime, timezone
from pathlib import Path

phases_path = sys.argv[1]
session_path = sys.argv[2]
goal_lock_path = sys.argv[3]
amendments_dir = sys.argv[4]

# Load data
with open(phases_path, "r", encoding="utf-8") as f:
    phases_data = json.load(f)

with open(session_path, "r", encoding="utf-8") as f:
    session_data = json.load(f)

phases = phases_data.get("phases", [])
if not phases:
    print("ERROR: No phases found in phases.json", file=sys.stderr)
    sys.exit(1)

# Build locked phases with criteria hashes
locked_phases = []
for phase in phases:
    phase_id = phase.get("phase_id", "")
    name = phase.get("name", "")
    criteria = phase.get("acceptance_criteria", [])

    # SHA256 of concatenated acceptance criteria strings
    # Hash normalization: preserve order + strip + remove empty strings
    normalized_criteria = [c.strip() for c in criteria if c.strip()]
    concatenated = "".join(normalized_criteria)
    criteria_hash = hashlib.sha256(concatenated.encode("utf-8")).hexdigest()

    locked_phases.append({
        "phase_id": phase_id,
        "name": name,
        "acceptance_criteria": criteria,
        "criteria_hash": criteria_hash
    })

# Build goal_lock document
goal_lock = {
    "task": session_data.get("task", ""),
    "phases": locked_phases,
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git_head": session_data.get("git_head_at_kickoff", None)
}

# Write goal_lock.json
with open(goal_lock_path, "w", encoding="utf-8") as f:
    json.dump(goal_lock, f, ensure_ascii=False, indent=2)
    f.write("\n")

# Write empty amendments log
amend_log = {
    "amendments": [],
    "goal_lock_created_at": goal_lock["created_at"],
    "note": "Each amendment records a change to acceptance_criteria with reason and new hash"
}
amend_path = Path(amendments_dir) / "amendments_log.json"
with open(amend_path, "w", encoding="utf-8") as f:
    json.dump(amend_log, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"goal_lock.json written with {len(locked_phases)} phases")
print(f"amendments_log.json written to {amend_path}")
PY

echo ""
pass "Goal lock created: $GOAL_LOCK_FILE"
info "Amendments directory: $AMENDMENTS_DIR/"

# Print summary of locked phases
python3 - "$GOAL_LOCK_FILE" <<'PY'
import json, sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

print(f"  Task: {data['task'][:80]}...")
for p in data["phases"]:
    print(f"  {p['phase_id']}: {p['criteria_hash'][:16]}... ({len(p['acceptance_criteria'])} criteria)")
print(f"  Git HEAD: {data.get('git_head', 'N/A')}")
PY

echo ""
echo -e "${GREEN}Done. Criteria are now locked. Use hmte-amend.sh to modify with audit trail.${NC}"
