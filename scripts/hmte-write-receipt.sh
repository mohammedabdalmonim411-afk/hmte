#!/bin/bash
# 用法: hmte-write-receipt.sh <phase_id> <attempt> <role> <instruction_path> <expected_output_path>
# Leader 在 delegate_task 之前调用
# 注意：此 receipt 表示 Leader 的委派意图，不等于真实委派证明

set -euo pipefail

PHASE_ID="${1:-}"
ATTEMPT="${2:-}"
ROLE="${3:-}"
INSTRUCTION="${4:-}"
OUTPUT_PATH="${5:-}"

# 参数校验
if [ -z "$PHASE_ID" ] || [ -z "$ATTEMPT" ] || [ -z "$ROLE" ] || [ -z "$INSTRUCTION" ] || [ -z "$OUTPUT_PATH" ]; then
    echo "Usage: hmte-write-receipt.sh <phase_id> <attempt> <role> <instruction_path> <expected_output_path>" >&2
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

RECEIPT_FILE="$DELEGATIONS_DIR/${PHASE_ID}_attempt_${ATTEMPT}_${ROLE}.json"

python3 -c "
import json, sys
from datetime import datetime, timezone

receipt = {
    'phase_id': sys.argv[1],
    'attempt': int(sys.argv[2]),
    'role': sys.argv[3],
    'delegated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'leader_session_id': sys.argv[6] if len(sys.argv) > 6 else 'unknown',
    'instruction_path': sys.argv[4],
    'expected_output_path': sys.argv[5],
    'trust_level': 'INTENT_ONLY',
    'delegate_task_params': {}
}

with open(sys.argv[7], 'w', encoding='utf-8') as f:
    json.dump(receipt, f, indent=2, ensure_ascii=False)
" "$PHASE_ID" "$ATTEMPT" "$ROLE" "$INSTRUCTION" "$OUTPUT_PATH" "${HMTE_SESSION_ID:-unknown}" "$RECEIPT_FILE" 

echo "Delegation intent receipt written: $RECEIPT_FILE (trust_level: INTENT_ONLY)"
