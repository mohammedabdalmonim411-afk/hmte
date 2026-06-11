#!/usr/bin/env bash
set -euo pipefail
CTRL=".phase_control"
python3 - "$CTRL" <<'PY'
import json, sys, os
from pathlib import Path
from datetime import datetime, timezone

ctrl = Path(sys.argv[1])
checks = []

def check(name, ok, detail=""):
    entry = {"name": name, "status": "PASS" if ok else "FAIL"}
    if detail:
        entry["detail"] = detail
    checks.append(entry)
    return ok

def result(status):
    print(json.dumps({
        "status": status,
        "checks": checks,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }, indent=2))
    sys.exit(0)

# 1. session.json
sp = ctrl / "session.json"
if not sp.exists():
    check("session.json", False, "not found")
    result("NOT_STARTED")
try:
    json.loads(sp.read_text())
    check("session.json", True)
except json.JSONDecodeError as e:
    check("session.json", False, f"invalid JSON: {e}")
    result("INVALID_START")

# 2. leader_kickoff.json
kp = ctrl / "instructions" / "leader_kickoff.json"
if kp.exists():
    check("leader_kickoff.json", True)
else:
    check("leader_kickoff.json", False, "not found")
    result("INVALID_START")

# 3. phases.json
pp = ctrl / "phases.json"
if not pp.exists():
    check("phases.json", False, "not found")
    result("KICKED_OFF")
check("phases.json", True)

try:
    phases_data = json.loads(pp.read_text())
    check("phases.json valid", True)
except json.JSONDecodeError:
    check("phases.json valid", False, "invalid JSON")
    result("INVALID_START")

phases = phases_data.get("phases", [])
if len(phases) == 0:
    check("phases array non-empty", False, "empty")
    result("PLANNED")
check("phases array non-empty", True)

# 4. phase_id/id 兼容检查
for i, p in enumerate(phases):
    pid = p.get("phase_id") or p.get("id")
    if pid is None:
        check(f"phase[{i}].phase_id", False, "missing both phase_id and id")
    elif "phase_id" not in p:
        check(f"phase[{i}].phase_id", True)
        checks[-1]["status"] = "WARN"
        checks[-1]["detail"] = "using 'id' instead of 'phase_id' (deprecated)"

# 5. Worker instructions
instr_dir = ctrl / "instructions"
worker_instrs = [f for f in instr_dir.glob("*_attempt_*_worker.json")]
if worker_instrs:
    check("worker instruction exists", True)
    result("READY_FOR_WORKER")
else:
    check("worker instruction exists", False, "no worker instructions found")
    result("PLANNED")
PY
