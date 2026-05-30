#!/usr/bin/env bash
set -euo pipefail

RUNTIME_SUBDIRS="instructions evidence verdicts logs delegations errors pids traces"
MODE="default"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive) MODE="archive"; shift ;;
        --force)   MODE="force"; shift ;;
        *)         break ;;
    esac
done

TASK="${1:?Usage: hmte-kickoff.sh [--archive|--force] <task description>}"
CTRL=".phase_control"

# 1. 先创建目录结构 + .gitkeep（幂等，保证空项目/首次使用行为一致）
mkdir -p "$CTRL"
for subdir in $RUNTIME_SUBDIRS; do
    mkdir -p "$CTRL/$subdir"
    touch "$CTRL/$subdir/.gitkeep"
done

# 2. 检查运行时残留（全部 8 个目录）
RESIDUAL_DIRS=""
for subdir in $RUNTIME_SUBDIRS; do
    count=$(find "$CTRL/$subdir" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        RESIDUAL_DIRS="$RESIDUAL_DIRS $subdir($count)"
    fi
done

if [ -f "$CTRL/session.json" ] || [ -n "$RESIDUAL_DIRS" ]; then
    case "$MODE" in
        default)
            echo "ERROR: Cannot start — active session or runtime residuals found." >&2
            [ -f "$CTRL/session.json" ] && echo "  session.json exists" >&2
            [ -n "$RESIDUAL_DIRS" ] && echo "  Residuals:$RESIDUAL_DIRS" >&2
            echo "Use --archive to save and restart, or HMTE_FORCE=1 --force to discard." >&2
            exit 1
            ;;
        archive)
            ARCHIVE_DIR=".phase_control_archive/$(date -u +%Y%m%d_%H%M%S)"
            mkdir -p "$ARCHIVE_DIR"
            cp -a "$CTRL"/. "$ARCHIVE_DIR"/
            echo "Archived to: $ARCHIVE_DIR"
            # 归档后清空运行时产物
            for subdir in $RUNTIME_SUBDIRS; do
                find "$CTRL/$subdir" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
            done
            rm -f "$CTRL/state.json" "$CTRL/session.json"
            ;;
        force)
            if [ "${HMTE_FORCE:-0}" != "1" ]; then
                echo "ERROR: --force requires HMTE_FORCE=1" >&2
                exit 1
            fi
            echo "WARNING: Force mode — discarding previous session data."
            for subdir in $RUNTIME_SUBDIRS; do
                find "$CTRL/$subdir" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
            done
            rm -f "$CTRL/state.json" "$CTRL/session.json"
            ;;
    esac
fi

# 3. 采集 Git 基线
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "null")
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "null")
GIT_DIRTY=false
[ -n "$(git status --short 2>/dev/null)" ] && GIT_DIRTY=true

# 4. 写 session.json（git_status 在 Python 内部通过 subprocess 获取）
python3 - "$CTRL" "$TASK" "$GIT_HEAD" "$GIT_BRANCH" "$GIT_DIRTY" <<'PY'
import json, sys, subprocess
from datetime import datetime, timezone
from pathlib import Path

ctrl, task, head, branch, dirty = sys.argv[1:6]

try:
    r = subprocess.run(['git', 'status', '--short'], capture_output=True, text=True, timeout=10)
    git_status = r.stdout.strip()
except Exception:
    git_status = ""

session = {
    "workflow": "HTE",
    "version": "1.3",
    "mode": "file-instruction",
    "task": task,
    "status": "KICKED_OFF",
    "required_first_action": "Leader must create .phase_control/phases.json before implementation",
    "git_head_at_kickoff": head if head != "null" else None,
    "git_branch_at_kickoff": branch if branch != "null" else None,
    "git_dirty_at_kickoff": dirty == "true",
    "git_status_at_kickoff": git_status,
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "session.json").write_text(
    json.dumps(session, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY

# 5. 写 leader_kickoff.json
python3 - "$CTRL" "$TASK" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, task = sys.argv[1], sys.argv[2]
instr = {
    "role": "Leader",
    "task": task,
    "required_actions": [
        "Read HERMES.md",
        "Read src/skills/hmte/SKILL.md",
        "Inspect project structure",
        "Create .phase_control/phases.json",
        "Create first Worker instruction"
    ],
    "forbidden_actions": [
        "Do not modify business code before phases.json exists",
        "Do not write Worker evidence as Leader",
        "Do not write Verifier verdict as Leader"
    ],
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "instructions", "leader_kickoff.json").write_text(
    json.dumps(instr, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY

# 6. 写初始 state.json
python3 - "$CTRL" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl = Path(sys.argv[1])
state = {
    "status": "KICKED_OFF",
    "current_phase_index": 0,
    "started_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
(ctrl / "state.json").write_text(
    json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY

echo ""
echo "✅ HTE session kicked off"
echo "📄 Session: $CTRL/session.json"
echo "📋 Leader instructions: $CTRL/instructions/leader_kickoff.json"
echo "🔖 Git baseline: $GIT_HEAD ($GIT_BRANCH)"
echo ""
echo "Next: Leader reads leader_kickoff.json, creates phases.json"
