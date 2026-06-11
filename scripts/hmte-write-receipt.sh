#!/bin/bash
# 用法: hmte-write-receipt.sh <phase_id> <attempt> <role> <instruction_path> <expected_output_path> [--worker-id <id>]
# Leader 在 delegate_task 之前调用
# 注意：此 receipt 表示 Leader 的委派意图，不等于真实委派证明

set -euo pipefail

PHASE_ID=""
ATTEMPT=""
ROLE=""
INSTRUCTION=""
OUTPUT_PATH=""
WORKER_ID=""

# 参数解析
while [ $# -gt 0 ]; do
    case "$1" in
        --worker-id)
            shift
            WORKER_ID="${1:-}"
            if [ -z "$WORKER_ID" ]; then
                echo "Missing value for --worker-id" >&2
                exit 1
            fi
            if ! [[ "$WORKER_ID" =~ ^[-A-Za-z0-9_]{1,64}$ ]]; then
                echo "Invalid worker_id: $WORKER_ID" >&2
                exit 1
            fi
            shift
            ;;
        *)
            if [ -z "$PHASE_ID" ]; then PHASE_ID="$1";
            elif [ -z "$ATTEMPT" ]; then ATTEMPT="$1";
            elif [ -z "$ROLE" ]; then ROLE="$1";
            elif [ -z "$INSTRUCTION" ]; then INSTRUCTION="$1";
            elif [ -z "$OUTPUT_PATH" ]; then OUTPUT_PATH="$1";
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# 参数校验
if [ -z "$PHASE_ID" ] || [ -z "$ATTEMPT" ] || [ -z "$ROLE" ] || [ -z "$INSTRUCTION" ] || [ -z "$OUTPUT_PATH" ]; then
    echo "Usage: hmte-write-receipt.sh <phase_id> <attempt> <role> <instruction_path> <expected_output_path> [--worker-id <id>]" >&2
    exit 1
fi

# phase_id 安全校验
if ! [[ "$PHASE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Invalid phase_id: $PHASE_ID" >&2
    exit 1
fi

# ATTEMPT 必须是正整数
if ! [[ "$ATTEMPT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid attempt: $ATTEMPT (must be positive integer)" >&2
    exit 1
fi

# ROLE 必须是 worker 或 verifier
if [[ "$ROLE" != "worker" && "$ROLE" != "verifier" ]]; then
    echo "Invalid role: $ROLE; must be worker or verifier" >&2
    exit 1
fi

# instruction_path 必须存在
if [ ! -f "$INSTRUCTION" ]; then
    echo "Instruction file not found: $INSTRUCTION" >&2
    exit 1
fi

# 确保 expected_output_path 的父目录存在
mkdir -p "$(dirname "$OUTPUT_PATH")"

DELEGATIONS_DIR=".phase_control/delegations"
mkdir -p "$DELEGATIONS_DIR"

# v1.7: Parallel worker receipt path
if [ -n "$WORKER_ID" ]; then
    RECEIPT_FILE="$DELEGATIONS_DIR/${PHASE_ID}_${WORKER_ID}_attempt_${ATTEMPT}_${ROLE}.json"
else
    RECEIPT_FILE="$DELEGATIONS_DIR/${PHASE_ID}_attempt_${ATTEMPT}_${ROLE}.json"
fi

python3 -c "
import json, sys
from datetime import datetime, timezone

ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

receipt = {
    'phase_id': sys.argv[1],
    'attempt': int(sys.argv[2]),
    'role': sys.argv[3],
    'delegated_at': ts,
    'timestamp': ts,
    'leader_session_id': sys.argv[6] if len(sys.argv) > 6 else 'unknown',
    'instruction_path': sys.argv[4],
    'leader_instruction_path': sys.argv[4],
    'expected_output_path': sys.argv[5],
    'trust_level': 'INTENT_ONLY',
    'delegation_trust_level': 'INTENT_ONLY',
    'delegation_method': 'delegate_task',
    'delegate_task_params': {}
}
if sys.argv[8]:
    receipt['worker_id'] = sys.argv[8]

with open(sys.argv[7], 'w', encoding='utf-8') as f:
    json.dump(receipt, f, indent=2, ensure_ascii=False)
" "$PHASE_ID" "$ATTEMPT" "$ROLE" "$INSTRUCTION" "$OUTPUT_PATH" "${HMTE_SESSION_ID:-unknown}" "$RECEIPT_FILE" "$WORKER_ID"

echo "Delegation intent receipt written: $RECEIPT_FILE (trust_level: INTENT_ONLY)"
