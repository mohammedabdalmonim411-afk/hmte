#!/usr/bin/env bash
# hmte-run.sh - HTE Orchestrator 包装脚本
# 调用 orchestrator.py 的 run/resume/status 子命令
#
# 用法:
#   hmte-run.sh run <goal>   运行完整工作流
#   hmte-run.sh resume       从上次失败处恢复
#   hmte-run.sh status       查看当前状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# 查找 orchestrator.py
ORCHESTRATOR=""
if [ -f "$SCRIPT_DIR/../src/skills/hmte/scripts/orchestrator.py" ]; then
    ORCHESTRATOR="$SCRIPT_DIR/../src/skills/hmte/scripts/orchestrator.py"
elif [ -n "${HMTE_SKILL_DIR:-}" ] && [ -f "$HMTE_SKILL_DIR/scripts/orchestrator.py" ]; then
    ORCHESTRATOR="$HMTE_SKILL_DIR/scripts/orchestrator.py"
else
    echo "❌ Cannot find orchestrator.py" >&2
    echo "Please ensure HTE is properly installed." >&2
    exit 1
fi

# 确保 Python3 可用
if ! command -v python3 &>/dev/null; then
    echo "❌ python3 is required but not found" >&2
    exit 1
fi

# 将 PROJECT_ROOT 作为最后一个参数传递给 orchestrator.py
exec python3 "$ORCHESTRATOR" "$@" "$PROJECT_ROOT"
