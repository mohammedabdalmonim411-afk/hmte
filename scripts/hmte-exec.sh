#!/usr/bin/env bash
# hmte-exec.sh - 命令执行包装器（强制过pretool_guard，自动记录证据）

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

# ---- 参数解析 ----
ATTEMPT=1
PHASE_ID=""
SEEN_PHASE_ID=false
PHASE_DONE=false

args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --attempt)
            shift
            if [ $# -eq 0 ] || [[ "$1" == --* && "$1" != "--" ]]; then
                error "Missing value for --attempt"
                exit 1
            fi
            ATTEMPT="$1"
            if ! [[ "$ATTEMPT" =~ ^[0-9]+$ ]]; then
                error "Invalid value for --attempt: $ATTEMPT (must be a positive integer)"
                exit 1
            fi
            shift
            ;;
        --)
            shift
            PHASE_DONE=true
            break
            ;;
        -*)
            error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [ "$SEEN_PHASE_ID" = true ]; then
                error "Unexpected argument: $1"
                error "Usage: hmte exec <phase_id> [--attempt N] -- <command>"
                exit 1
            fi
            PHASE_ID="$1"
            SEEN_PHASE_ID=true
            shift
            ;;
    esac
done

# 校验 phase_id
if [ -z "$PHASE_ID" ]; then
    error "Missing phase_id"
    error "Usage: hmte exec <phase_id> [--attempt N] -- <command>"
    exit 1
fi

if [[ "$PHASE_ID" == *"../"* ]]; then
    error "Invalid phase_id: contains '../'"
    exit 1
fi

if [[ "$PHASE_ID" == *" "* ]]; then
    error "Invalid phase_id: contains spaces"
    exit 1
fi

# 校验命令
if [ "$PHASE_DONE" != true ]; then
    error "Missing '--' separator"
    error "Usage: hmte exec <phase_id> [--attempt N] -- <command>"
    exit 1
fi

if [ $# -eq 0 ]; then
    error "Missing command after '--'"
    error "Usage: hmte exec <phase_id> [--attempt N] -- <command>"
    exit 1
fi

CMD_ARGS=("$@")   # 保留数组，不再拼成字符串
COMMAND_STR="$(printf '%q ' "${CMD_ARGS[@]}")"
COMMAND_STR="${COMMAND_STR% }"

# 查找skill目录
SKILL_DIR="${HMTE_SKILL_DIR:-$HOME/.hermes/profiles/default/skills/hmte}"
if [ ! -d "$SKILL_DIR" ]; then
    error "HTE skill directory not found: $SKILL_DIR"
    error "Please set HMTE_SKILL_DIR or install HTE to Hermes"
    exit 1
fi

# 确保日志目录存在
LOG_DIR=".phase_control/logs"
mkdir -p "$LOG_DIR"

# 1. 安全检查 - 强制过 pretool_guard
info "Running pretool_guard checks..."
if ! bash "$SKILL_DIR/hooks/pretool_guard.sh" Bash "$COMMAND_STR"; then
    error "Command blocked by pretool_guard"
    exit 1
fi
success "Pretool guard passed"

# 2. 准备日志文件名
LOG_FILE="$LOG_DIR/${PHASE_ID}_attempt_${ATTEMPT}.commands.jsonl"
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

info "Executing: $COMMAND_STR"
echo ""

# 3. 执行命令并捕获输出到临时文件
OUTPUT_FILE=$(mktemp)
trap 'rm -f "$OUTPUT_FILE"' EXIT

set +e
"${CMD_ARGS[@]}" >"$OUTPUT_FILE" 2>&1
EXIT_CODE=$?
set -e

ENDED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 4. 显示输出
cat "$OUTPUT_FILE"

# 5. 用 Python json.dump 追加 JSONL（从临时文件读取输出）
python3 - "$LOG_FILE" "$PHASE_ID" "$ATTEMPT" "$COMMAND_STR" "$EXIT_CODE" "$STARTED_AT" "$ENDED_AT" "$OUTPUT_FILE" <<'PY'
import json, sys
from pathlib import Path

log_file, phase_id, attempt, command, exit_code, started_at, ended_at, output_file = sys.argv[1:9]
text = Path(output_file).read_text(encoding="utf-8", errors="replace")

entry = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "command": command,
    "exit_code": int(exit_code),
    "runner": "hmte exec",
    "started_at": started_at,
    "ended_at": ended_at,
    "output_tail": text[-2000:]
}

with open(log_file, "a", encoding="utf-8") as f:
    json.dump(entry, f, ensure_ascii=False)
    f.write("\n")
PY

# 6. 如果命令成功，自动采集Git变更
if [ $EXIT_CODE -eq 0 ]; then
    if git rev-parse --git-dir > /dev/null 2>&1; then
        info "Collecting Git changes..."
        
        # 采集变更文件列表
        git diff --name-only > "$LOG_DIR/${PHASE_ID}_attempt_${ATTEMPT}-changed-files.txt" 2>/dev/null || true
        
        # 采集变更统计
        git diff --stat > "$LOG_DIR/${PHASE_ID}_attempt_${ATTEMPT}-diff-stat.txt" 2>/dev/null || true
        
        # 采集未暂存的变更数量
        CHANGED_COUNT=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
        if [ "$CHANGED_COUNT" -gt 0 ]; then
            success "Collected $CHANGED_COUNT changed file(s)"
        fi
    fi
fi

# 7. 显示结果
echo ""
if [ $EXIT_CODE -eq 0 ]; then
    success "Command completed successfully"
    success "Logged to: $LOG_FILE"
else
    error "Command failed with exit code: $EXIT_CODE"
    error "Logged to: $LOG_FILE"
fi

exit $EXIT_CODE
