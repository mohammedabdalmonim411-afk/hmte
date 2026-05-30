#!/bin/bash
# hmte-final-check.sh - 检查 HTE 文件协议完整性
# 验证所有 phase 的文件存在性、verdict 状态、phase_gate 通过情况

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}❌${NC} $*" >&2; }

# 统计变量
TOTAL_CHECKS=0
PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

# 检查函数
check() {
    local name="$1"
    local condition="$2"
    local detail="${3:-}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if eval "$condition"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        if [ -n "$detail" ]; then
            success "$name: $detail"
        else
            success "$name"
        fi
        return 0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        if [ -n "$detail" ]; then
            error "$name: $detail"
            FAILURES+=("$name: $detail")
        else
            error "$name"
            FAILURES+=("$name")
        fi
        return 1
    fi
}

# JSON 验证函数
validate_json() {
    local file="$1"
    python3 -c "import json, sys; json.load(open('$file'))" 2>/dev/null
}

# 获取 phase 的最新 attempt
get_latest_attempt() {
    local phase_id="$1"
    local max_attempt=0
    
    for verdict_file in .phase_control/verdicts/${phase_id}_attempt_*.json; do
        if [ -f "$verdict_file" ]; then
            local attempt=$(basename "$verdict_file" | sed -n "s/^${phase_id}_attempt_\([0-9][0-9]*\)\.json$/\1/p")
            if [ -n "$attempt" ] && [ "$attempt" -gt "$max_attempt" ]; then
                max_attempt=$attempt
            fi
        fi
    done
    
    echo "$max_attempt"
}

# 检查 verdict 状态
check_verdict_status() {
    local verdict_file="$1"
    python3 -c "
import json, sys
with open('$verdict_file') as f:
    data = json.load(f)
    status = data.get('status', '')
    sys.exit(0 if status == 'PASS' else 1)
" 2>/dev/null
}

# 检查 phase_gate
check_phase_gate() {
    local phase_id="$1"
    local attempt="$2"
    
    # 查找 phase_gate.sh
    local phase_gate_script=""
    if [ -f "src/skills/hmte/scripts/phase_gate.sh" ]; then
        phase_gate_script="src/skills/hmte/scripts/phase_gate.sh"
    elif [ -f "$HOME/.hermes/profiles/default/skills/hmte/scripts/phase_gate.sh" ]; then
        phase_gate_script="$HOME/.hermes/profiles/default/skills/hmte/scripts/phase_gate.sh"
    else
        return 1
    fi
    
    bash "$phase_gate_script" "$phase_id" --attempt "$attempt" >/dev/null 2>&1
}

echo "=================================================="
echo "HTE Final Check - 文件协议完整性验证"
echo "=================================================="
echo ""

# ============================================================
# 1. 检查 session.json
# ============================================================
info "检查 session.json..."
check "session.json 存在" "[ -f .phase_control/session.json ]"
check "session.json 合法 JSON" "validate_json .phase_control/session.json"
echo ""

# ============================================================
# 2. 检查 phases.json
# ============================================================
info "检查 phases.json..."
check "phases.json 存在" "[ -f .phase_control/phases.json ]"
check "phases.json 合法 JSON" "validate_json .phase_control/phases.json"
echo ""

# ============================================================
# 3. 检查每个 phase 的文件完整性
# ============================================================
if [ -f .phase_control/phases.json ]; then
    info "检查各 phase 文件完整性..."
    
    # 读取 phases
    PHASE_IDS=$(python3 -c "
import json
with open('.phase_control/phases.json') as f:
    data = json.load(f)
    for phase in data.get('phases', []):
        print(phase['phase_id'])
" 2>/dev/null)
    
    for phase_id in $PHASE_IDS; do
        echo ""
        info "Phase: $phase_id"
        
        # 获取最新 attempt
        attempt=$(get_latest_attempt "$phase_id")
        
        if [ "$attempt" -eq 0 ]; then
            warn "  未找到任何 attempt，跳过"
            continue
        fi
        
        info "  检查 attempt $attempt..."
        
        # 检查 7 个文件
        check "  worker instruction" "[ -f .phase_control/instructions/${phase_id}_attempt_${attempt}_worker.json ]"
        check "  worker receipt" "[ -f .phase_control/delegations/${phase_id}_attempt_${attempt}_worker.json ]"
        check "  verifier instruction" "[ -f .phase_control/instructions/${phase_id}_attempt_${attempt}_verifier.json ]"
        check "  verifier receipt" "[ -f .phase_control/delegations/${phase_id}_attempt_${attempt}_verifier.json ]"
        check "  command log" "[ -f .phase_control/logs/${phase_id}_attempt_${attempt}.commands.jsonl ]"
        check "  evidence" "[ -f .phase_control/evidence/${phase_id}_attempt_${attempt}.json ]"
        check "  verdict" "[ -f .phase_control/verdicts/${phase_id}_attempt_${attempt}.json ]"
        
        # 检查 verdict 状态
        if [ -f ".phase_control/verdicts/${phase_id}_attempt_${attempt}.json" ]; then
            if check_verdict_status ".phase_control/verdicts/${phase_id}_attempt_${attempt}.json"; then
                success "  verdict status = PASS"
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                error "  verdict status ≠ PASS"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                FAILURES+=("${phase_id}: verdict status ≠ PASS")
            fi
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        fi
        
        # 检查 phase_gate
        if check_phase_gate "$phase_id" "$attempt"; then
            success "  phase_gate 通过"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "  phase_gate 未通过"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("${phase_id}: phase_gate 未通过")
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    done
fi

echo ""

# ============================================================
# 4. 检查 final_audit
# ============================================================
info "检查 final_audit..."

# 查找 final_audit 的最新 attempt
final_audit_attempt=$(get_latest_attempt "final_audit")

if [ "$final_audit_attempt" -gt 0 ]; then
    info "  检查 final_audit attempt $final_audit_attempt..."
    
    check "  final_audit evidence" "[ -f .phase_control/evidence/final_audit_attempt_${final_audit_attempt}.json ]"
    check "  final_audit verdict" "[ -f .phase_control/verdicts/final_audit_attempt_${final_audit_attempt}.json ]"
    check "  final_audit command log" "[ -f .phase_control/logs/final_audit_attempt_${final_audit_attempt}.commands.jsonl ]"
    
    # 检查 final_audit verdict 状态
    if [ -f ".phase_control/verdicts/final_audit_attempt_${final_audit_attempt}.json" ]; then
        if check_verdict_status ".phase_control/verdicts/final_audit_attempt_${final_audit_attempt}.json"; then
            success "  final_audit verdict status = PASS"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "  final_audit verdict status ≠ PASS"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("final_audit: verdict status ≠ PASS")
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
    
    # 检查 final_audit phase_gate
    if check_phase_gate "final_audit" "$final_audit_attempt"; then
        success "  final_audit phase_gate 通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        error "  final_audit phase_gate 未通过"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("final_audit: phase_gate 未通过")
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
else
    warn "  未找到 final_audit，跳过"
fi

echo ""
echo "=================================================="
echo "检查完成"
echo "=================================================="
echo ""
echo "总检查项: $TOTAL_CHECKS"
echo "通过: $PASS_COUNT"
echo "失败: $FAIL_COUNT"
echo ""

# ============================================================
# 5. 输出结果
# ============================================================
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "=================================================="
    error "检查失败！以下项目未通过："
    echo "=================================================="
    for failure in "${FAILURES[@]}"; do
        echo "  ❌ $failure"
    done
    echo ""
    exit 1
else
    echo "=================================================="
    success "所有检查通过！文件协议完整性验证成功。"
    echo "=================================================="
    echo ""
    exit 0
fi
