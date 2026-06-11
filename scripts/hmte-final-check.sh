#!/bin/bash
# hmte-final-check.sh - TAF 文件协议完整性验证（v2 - P0-5 重建状态版）
#
# v2 变更:
#   - 不信任 state.json，从 phases.json 枚举所有 phase
#   - 集成 Goalpost Lock (P0-1)
#   - 集成 Instruction Lint (P0-2)
#   - 集成 Evidence Claim Verification (P0-3)
#   - 集成 Verifier Minimum Audit (via phase_gate P0-4)
#   - release 模式更严格
#
# 用法:
#   bash scripts/hmte-final-check.sh [--mode dev|release]

set -euo pipefail

MODE="${HMTE_FINAL_CHECK_MODE:-dev}"
for arg in "$@"; do
    case "$arg" in
        --mode) shift; MODE="${1:-$MODE}"; shift 2>/dev/null || true ;;
    esac
done

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
WARN_COUNT=0
FAILURES=()

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

warn_check() {
    local name="$1"
    local condition="$2"
    local detail="${3:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if eval "$condition"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        success "$name"
    else
        WARN_COUNT=$((WARN_COUNT + 1))
        if [ -n "$detail" ]; then
            warn "$name: $detail"
        else
            warn "$name"
        fi
        # In release mode, warnings are failures
        if [ "$MODE" = "release" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("$name (WARN→FAIL in release)")
        fi
    fi
}

# JSON 验证函数
validate_json() {
    local file="$1"
    python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$file" 2>/dev/null
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

    local phase_gate_script=""
    # Priority: local wrapper > src/skills > HMTE_SKILL_DIR > installed
    if [ -f "scripts/phase_gate.sh" ]; then
        phase_gate_script="scripts/phase_gate.sh"
    elif [ -f "src/skills/hmte/scripts/phase_gate.sh" ]; then
        phase_gate_script="src/skills/hmte/scripts/phase_gate.sh"
    elif [ -n "${HMTE_SKILL_DIR:-}" ] && [ -f "$HMTE_SKILL_DIR/scripts/phase_gate.sh" ]; then
        phase_gate_script="$HMTE_SKILL_DIR/scripts/phase_gate.sh"
    elif [ -f "$HOME/.hermes/profiles/default/skills/hmte/scripts/phase_gate.sh" ]; then
        phase_gate_script="$HOME/.hermes/profiles/default/skills/hmte/scripts/phase_gate.sh"
    else
        return 1
    fi

    bash "$phase_gate_script" "$phase_id" --attempt "$attempt" >/dev/null 2>&1
}

get_phase_mode() {
    local phase_id="$1"
    python3 - "$phase_id" <<'PY' 2>/dev/null || echo "sequential"
import json
import sys

phase_id = sys.argv[1]
with open(".phase_control/phases.json", encoding="utf-8") as f:
    data = json.load(f)
for phase in data.get("phases", []):
    pid = phase.get("phase_id") or phase.get("id") or ""
    if pid == phase_id:
        print(phase.get("execution_mode") or "sequential")
        raise SystemExit(0)
print("sequential")
PY
}

get_parallel_worker_ids() {
    local phase_id="$1"
    python3 - "$phase_id" <<'PY' 2>/dev/null || true
import json
import sys

phase_id = sys.argv[1]
with open(".phase_control/phases.json", encoding="utf-8") as f:
    data = json.load(f)
for phase in data.get("phases", []):
    pid = phase.get("phase_id") or phase.get("id") or ""
    if pid == phase_id:
        for worker in phase.get("parallel_workers", []) or []:
            worker_id = worker.get("worker_id", "")
            if worker_id:
                print(worker_id)
        break
PY
}

valid_worker_id() {
    local worker_id="$1"
    [[ "$worker_id" =~ ^[-A-Za-z0-9_]{1,64}$ ]]
}

parallel_worker_instruction_exists() {
    local phase_id="$1"
    local worker_id="$2"
    local attempt="$3"
    local zero_attempt=$((attempt - 1))

    [ -f ".phase_control/instructions/${phase_id}_${worker_id}_attempt_${attempt}_worker.json" ] || \
        [ -f ".phase_control/instructions/${phase_id}_${worker_id}_worker_${zero_attempt}.json" ]
}

parallel_verifier_instruction_exists() {
    local phase_id="$1"
    local attempt="$2"
    local zero_attempt=$((attempt - 1))

    [ -f ".phase_control/instructions/${phase_id}_attempt_${attempt}_verifier.json" ] || \
        [ -f ".phase_control/instructions/${phase_id}_verifier_${zero_attempt}.json" ]
}

echo "=================================================="
echo "TAF Final Check v2 — 文件协议完整性验证"
echo "模式: $MODE"
echo "=================================================="
echo ""

# ============================================================
# 1. Release repository mode: no active runtime session
# ============================================================
ACTIVE_SESSION=false
if [ -f .phase_control/session.json ] || [ -f .phase_control/phases.json ]; then
    ACTIVE_SESSION=true
fi

if [ "$MODE" = "release" ] && ! $ACTIVE_SESSION; then
    info "Release repository mode: no active .phase_control session; runtime chain checks skipped."
    check "hmte-eval.sh 存在" "[ -f scripts/hmte-eval.sh ]"
    check "hmte-release-gate.sh 存在" "[ -f scripts/hmte-release-gate.sh ]"
    check "phase_gate.sh 存在" "[ -f scripts/phase_gate.sh ] || [ -f src/skills/hmte/scripts/phase_gate.sh ]"
    check "protocol 文档存在" "[ -f docs/HTE_PROTOCOL.md ]"

    echo ""
    echo "=================================================="
    echo "检查完成"
    echo "=================================================="
    echo ""
    echo "模式: $MODE"
    echo "总检查项: $TOTAL_CHECKS"
    echo "通过: $PASS_COUNT"
    echo "失败: $FAIL_COUNT"
    echo "警告: $WARN_COUNT"
    echo ""

    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "=================================================="
        error "检查失败！以下项目未通过："
        echo "=================================================="
        for failure in "${FAILURES[@]+"${FAILURES[@]}"}"; do
            echo "  ❌ $failure"
        done
        echo ""
        exit 1
    fi

    echo "=================================================="
    success "仓库 release 静态检查通过；未发现 active runtime session。"
    echo "=================================================="
    echo ""
    exit 0
fi

# ============================================================
# 2. 检查 session.json（不信任其状态字段）
# ============================================================
info "检查 session.json..."
check "session.json 存在" "[ -f .phase_control/session.json ]"
check "session.json 合法 JSON" "validate_json .phase_control/session.json"
echo ""

# ============================================================
# 3. 检查 phases.json（从 phases.json 枚举，不信任 state）
# ============================================================
info "检查 phases.json..."
check "phases.json 存在" "[ -f .phase_control/phases.json ]"
check "phases.json 合法 JSON" "validate_json .phase_control/phases.json"

# P0-1: Canonical schema validation
info "P0-1: Canonical schema validation..."
if [ -f "scripts/hmte-validate-phases.sh" ]; then
    if HMTE_LINT_MODE="$MODE" bash scripts/hmte-validate-phases.sh .phase_control/phases.json 2>&1; then
        success "phases.json schema valid (canonical)"
    else
        WARN_COUNT=$((WARN_COUNT + 1))
        warn "phases.json schema validation failed"
        if [ "$MODE" = "release" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("phases.json canonical schema validation (WARN→FAIL in release)")
            error "FATAL: phases.json must pass canonical schema validation in release mode"
        fi
    fi
else
    if [ "$MODE" = "release" ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("hmte-validate-phases.sh not found (required in release mode)")
        error "FATAL: Cannot validate phases.json schema in release mode without validator"
    else
        WARN_COUNT=$((WARN_COUNT + 1))
        warn "hmte-validate-phases.sh not found (schema validation skipped in dev mode)"
    fi
fi

echo ""

# ============================================================
# 3. P0-1: Goalpost Lock 检查
# ============================================================
info "P0-1: Goalpost Lock..."
if [ -f ".phase_control/goal_lock.json" ]; then
    check "goal_lock.json 存在且合法" "validate_json .phase_control/goal_lock.json"

    # 对比 phases.json 与 goal_lock
    GOAL_RESULT=$(python3 -c "
import json, sys, hashlib, os, glob

MODE = '$MODE'

with open('.phase_control/goal_lock.json') as f:
    goal = json.load(f)
with open('.phase_control/phases.json') as f:
    phases = json.load(f)

goal_phases = {p['phase_id']: p for p in goal.get('phases', [])}
current_phases_list = phases.get('phases', [])
current_phases = {p.get('phase_id', p.get('id', '')): p for p in current_phases_list}

issues = []

# Helper: normalize criteria for hash calculation
def normalize_criteria(criteria):
    if isinstance(criteria, list):
        return [c.strip() for c in criteria if isinstance(c, str) and c.strip()]
    elif isinstance(criteria, str):
        stripped = criteria.strip()
        return [stripped] if stripped else []
    elif criteria is None:
        return []
    else:
        # 其他类型转字符串
        val = str(criteria).strip()
        return [val] if val else []

def compute_hash(criteria):
    normalized = normalize_criteria(criteria)
    concatenated = json.dumps(normalized, ensure_ascii=False, separators=(',', ':'))
    return hashlib.sha256(concatenated.encode('utf-8')).hexdigest()

# Check for deleted phases
for pid in goal_phases:
    if pid not in current_phases:
        issues.append(f'phase deleted: {pid}')

# Check for newly added phases (not in goal_lock)
for pid in current_phases:
    if pid not in goal_phases:
        # Check if there's an amendment authorizing this new phase
        amended = False
        amend_dir = '.phase_control/amendments'
        if os.path.isdir(amend_dir):
            for af in glob.glob(f'{amend_dir}/*.json'):
                with open(af) as f:
                    amend = json.load(f)
                if amend.get('action') == 'add_phase' and amend.get('phase_id') == pid:
                    # 必需字段检查
                    if 'created_at' not in amend:
                        issues.append(f'new phase {pid}: amendment missing created_at')
                        continue
                    if 'scope_impact' not in amend:
                        issues.append(f'new phase {pid}: amendment missing scope_impact')
                        continue
                    
                    scope_impact = amend.get('scope_impact', '')
                    if scope_impact not in ['expand', 'clarify', 'neutral', 'reduce']:
                        issues.append(f'new phase {pid}: invalid scope_impact={scope_impact}')
                        continue
                    
                    reason = amend.get('reason', '').strip()
                    # Reason length check: add_phase >= 20 chars
                    if len(reason) < 20:
                        issues.append(f'new phase {pid}: reason too short ({len(reason)} < 20 chars)')
                        continue
                    
                    # Phase binding check: must have new_hash matching current criteria
                    if 'new_hash' not in amend:
                        issues.append(f'new phase {pid}: amendment missing new_hash')
                        continue
                    
                    new_hash = amend.get('new_hash', '')
                    current_hash = compute_hash(current_phases[pid].get('acceptance_criteria', []))
                    if new_hash != current_hash:
                        issues.append(f'new phase {pid}: amendment hash mismatch (expected {current_hash}, got {new_hash})')
                        continue
                    
                    # Release mode: check scope_impact
                    if MODE == 'release' and scope_impact == 'reduce':
                        issues.append(f'new phase {pid}: scope_impact=reduce blocked in release mode')
                        continue
                    
                    amended = True
                    break
        if not amended:
            issues.append(f'new phase added without valid amendment: {pid}')

# Check for weakened criteria
for pid, gp in goal_phases.items():
    if pid not in current_phases:
        continue
    cp = current_phases[pid]
    goal_criteria = normalize_criteria(gp.get('acceptance_criteria', []))
    current_criteria = normalize_criteria(cp.get('acceptance_criteria', []))
    # Check for deleted criteria
    for gc in goal_criteria:
        if gc not in current_criteria:
            # Check if there's an amendment
            amended = False
            amend_dir = '.phase_control/amendments'
            if os.path.isdir(amend_dir):
                for af in glob.glob(f'{amend_dir}/*.json'):
                    with open(af) as f:
                        amend = json.load(f)
                    if amend.get('phase_id') == pid and amend.get('action') == 'modify_criteria':
                        old_val = amend.get('old', '')
                        if old_val == gc:
                            # 必需字段检查
                            if 'created_at' not in amend:
                                issues.append(f'{pid}: amendment missing created_at')
                                continue
                            if 'scope_impact' not in amend:
                                issues.append(f'{pid}: amendment missing scope_impact')
                                continue
                            
                            scope_impact = amend.get('scope_impact', '')
                            if scope_impact not in ['expand', 'clarify', 'neutral', 'reduce']:
                                issues.append(f'{pid}: invalid scope_impact={scope_impact}')
                                continue
                            
                            reason = amend.get('reason', '').strip()
                            # Reason length check: modify_criteria >= 30 chars
                            if len(reason) < 30:
                                issues.append(f'{pid}: reason too short ({len(reason)} < 30 chars)')
                                continue
                            
                            # Hash binding check
                            if 'old_hash' not in amend or 'new_hash' not in amend:
                                issues.append(f'{pid}: amendment missing old_hash or new_hash')
                                continue
                            
                            new_hash = amend.get('new_hash', '')
                            current_hash = compute_hash(current_criteria)
                            if new_hash != current_hash:
                                issues.append(f'{pid}: amendment hash mismatch')
                                continue
                            
                            # Release mode: check scope_impact
                            if MODE == 'release' and scope_impact == 'reduce':
                                issues.append(f'{pid}: scope_impact=reduce blocked in release mode')
                                continue
                            
                            amended = True
                            break
            if not amended:
                issues.append(f'{pid}: criteria deleted without valid amendment: {gc[:60]}')

if issues:
    print('FAIL:' + '; '.join(issues))
else:
    print('PASS')
" 2>/dev/null || echo "FAIL:goal_lock parse error")

    if [[ "$GOAL_RESULT" == PASS ]]; then
        success "Goalpost Lock: 验收标准未弱化"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        error "Goalpost Lock: $GOAL_RESULT"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("Goalpost Lock: criteria weakened or phase deleted")
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
else
    if [ "$MODE" = "release" ]; then
        error "goal_lock.json 不存在 — release 模式要求必须锁定验收标准"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        FAILURES+=("Goalpost Lock: goal_lock.json missing (required in release mode)")
    else
        warn "goal_lock.json 不存在，跳过 Goalpost Lock 检查"
        WARN_COUNT=$((WARN_COUNT + 1))
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
fi
echo ""

# ============================================================
# 4. 检查每个 phase 的文件完整性（从 phases.json 枚举）
# ============================================================
if [ -f .phase_control/phases.json ]; then
    info "检查各 phase 文件完整性..."

    PHASE_IDS=$(python3 -c "
import json
with open('.phase_control/phases.json') as f:
    data = json.load(f)
for phase in data.get('phases', []):
    pid = phase.get('phase_id', phase.get('id', ''))
    print(pid)
" 2>/dev/null)

    for phase_id in $PHASE_IDS; do
        echo ""
        info "Phase: $phase_id"

        attempt=$(get_latest_attempt "$phase_id")

        if [ "$attempt" -eq 0 ]; then
            error "  未找到任何 attempt"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            FAILURES+=("${phase_id}: no attempt found")
            continue
        fi

        info "  检查 attempt $attempt..."

        phase_mode="$(get_phase_mode "$phase_id")"

        if [ "$phase_mode" = "parallel_safe" ]; then
            info "  execution_mode=parallel_safe: 检查 shard 文件链..."

            # parallel_safe keeps one verifier/join verdict, but worker artifacts are per shard.
            check "  verifier instruction" "parallel_verifier_instruction_exists '$phase_id' '$attempt'"
            check "  verifier receipt" "[ -f .phase_control/delegations/${phase_id}_attempt_${attempt}_verifier.json ]"
            check "  verdict" "[ -f .phase_control/verdicts/${phase_id}_attempt_${attempt}.json ]"

            worker_ids="$(get_parallel_worker_ids "$phase_id")"
            if [ -z "$worker_ids" ]; then
                error "  parallel_workers 为空"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
                FAILURES+=("${phase_id}: parallel_workers empty")
            else
                while IFS= read -r worker_id; do
                    [ -z "$worker_id" ] && continue
                    info "  Worker shard: $worker_id"

                    if valid_worker_id "$worker_id"; then
                        success "    worker_id 合法"
                        PASS_COUNT=$((PASS_COUNT + 1))
                    else
                        error "    worker_id 非法: $worker_id"
                        FAIL_COUNT=$((FAIL_COUNT + 1))
                        FAILURES+=("${phase_id}/${worker_id}: invalid worker_id")
                    fi
                    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

                    if valid_worker_id "$worker_id"; then
                        check "    worker instruction" "parallel_worker_instruction_exists '$phase_id' '$worker_id' '$attempt'"
                        check "    worker receipt" "[ -f .phase_control/delegations/${phase_id}_${worker_id}_attempt_${attempt}_worker.json ]"
                        check "    command log" "[ -f .phase_control/logs/${phase_id}_${worker_id}_attempt_${attempt}.commands.jsonl ]"
                        check "    evidence" "[ -f .phase_control/evidence/${phase_id}_${worker_id}_attempt_${attempt}.json ]"
                    fi
                done <<< "$worker_ids"
            fi
        else
            # Sequential phases keep the legacy 7-file chain.
            check "  worker instruction" "[ -f .phase_control/instructions/${phase_id}_attempt_${attempt}_worker.json ]"
            check "  worker receipt" "[ -f .phase_control/delegations/${phase_id}_attempt_${attempt}_worker.json ]"
            check "  verifier instruction" "[ -f .phase_control/instructions/${phase_id}_attempt_${attempt}_verifier.json ]"
            check "  verifier receipt" "[ -f .phase_control/delegations/${phase_id}_attempt_${attempt}_verifier.json ]"
            check "  command log" "[ -f .phase_control/logs/${phase_id}_attempt_${attempt}.commands.jsonl ]"
            check "  evidence" "[ -f .phase_control/evidence/${phase_id}_attempt_${attempt}.json ]"
            check "  verdict" "[ -f .phase_control/verdicts/${phase_id}_attempt_${attempt}.json ]"
        fi

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

        # 检查 phase_gate（包含 P0-4 Verifier Minimum Audit）
        if check_phase_gate "$phase_id" "$attempt"; then
            success "  phase_gate 通过 (含 Verifier Minimum Audit)"
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
# 5. P0-2: Instruction Lint
# ============================================================
info "P0-2: Instruction Lint..."
if [ -f "scripts/hmte-lint-instructions.sh" ]; then
    LINT_MODE="$MODE"
    set +e
    bash scripts/hmte-lint-instructions.sh --mode "$LINT_MODE" >/dev/null 2>&1
    LINT_EXIT=$?
    set -e

    if [ "$LINT_EXIT" -eq 0 ]; then
        success "Instruction Lint 通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        error "Instruction Lint 失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("Instruction Lint: 发现危险弱化语句")
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
else
    warn "scripts/hmte-lint-instructions.sh 不存在，跳过"
    WARN_COUNT=$((WARN_COUNT + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi
echo ""

# ============================================================
# 6. P0-3: Evidence Claim Verification
# ============================================================
info "P0-3: Evidence Claim Verification..."
if [ -f "scripts/hmte-verify-claims.sh" ]; then
    set +e
    bash scripts/hmte-verify-claims.sh --mode "$MODE" >/dev/null 2>&1
    CLAIMS_EXIT=$?
    set -e

    if [ "$CLAIMS_EXIT" -eq 0 ]; then
        success "Evidence Claim Verification 通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        error "Evidence Claim Verification 失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("Evidence Claim Verification: 认领文件验证失败")
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
else
    warn "scripts/hmte-verify-claims.sh 不存在，跳过"
    WARN_COUNT=$((WARN_COUNT + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi
echo ""

# ============================================================
# 7. 检查 final_audit 覆盖所有 phase
# ============================================================
info "检查 final_audit..."
final_audit_attempt=$(get_latest_attempt "final_audit")

if [ "$final_audit_attempt" -gt 0 ]; then
    info "  检查 final_audit attempt $final_audit_attempt..."

    check "  final_audit evidence" "[ -f .phase_control/evidence/final_audit_attempt_${final_audit_attempt}.json ]"
    check "  final_audit verdict" "[ -f .phase_control/verdicts/final_audit_attempt_${final_audit_attempt}.json ]"
    check "  final_audit command log" "[ -f .phase_control/logs/final_audit_attempt_${final_audit_attempt}.commands.jsonl ]"

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

    if check_phase_gate "final_audit" "$final_audit_attempt"; then
        success "  final_audit phase_gate 通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        error "  final_audit phase_gate 未通过"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("final_audit: phase_gate 未通过")
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # 检查 final_audit 是否覆盖所有 phase
    if [ -f ".phase_control/evidence/final_audit_attempt_${final_audit_attempt}.json" ]; then
        COVERAGE=$(python3 -c "
import json
with open('.phase_control/phases.json') as f:
    phases = json.load(f)
with open('.phase_control/evidence/final_audit_attempt_${final_audit_attempt}.json') as f:
    audit = json.load(f)
all_pids = set(p.get('phase_id', p.get('id', '')) for p in phases.get('phases', []))
covered = audit.get('covered_phases')
if isinstance(covered, list) and all(isinstance(pid, str) for pid in covered):
    covered_set = set(pid for pid in covered if pid)
    missing = [pid for pid in all_pids if pid and pid not in covered_set]
    if missing:
        print('FAIL:未覆盖 ' + ', '.join(missing))
    else:
        print('PASS')
else:
    audit_text = json.dumps(audit)
    missing = [pid for pid in all_pids if pid and pid not in audit_text]
    if missing:
        print('FAIL:未覆盖 ' + ', '.join(missing))
    else:
        print('PASS')
" 2>/dev/null || echo "FAIL:coverage check error")

        if [[ "$COVERAGE" == PASS ]]; then
            success "  final_audit 覆盖所有 phase"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "  $COVERAGE"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("final_audit: $COVERAGE")
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
else
    if [ "$MODE" = "release" ]; then
        error "  final_audit 不存在 — release 模式下完成声明前必须有 final_audit"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("final_audit: missing (required in release mode)")
    else
        warn "  未找到 final_audit，跳过（dev 模式不阻断）"
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi
echo ""

# ============================================================
# 8. Release 模式额外检查
# ============================================================
if [ "$MODE" = "release" ]; then
    info "Release 模式额外检查..."

    # 检查 unresolved_risks 处置
    if [ -f ".phase_control/evidence/final_audit_attempt_${final_audit_attempt}.json" ]; then
        RISKS=$(python3 -c "
import json
with open('.phase_control/evidence/final_audit_attempt_${final_audit_attempt}.json') as f:
    audit = json.load(f)
risks = audit.get('unresolved_risks', [])
if risks and risks != ['none'] and risks != []:
    print('WARN:' + '; '.join(str(r) for r in risks))
else:
    print('PASS')
" 2>/dev/null || echo "PASS")

        if [[ "$RISKS" == WARN* ]]; then
            error "  Release 模式: 存在未解决风险 — $RISKS"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("Release: unresolved risks without disposition")
        else
            success "  无未解决风险"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi

    # 检查 WARN 级别问题
    if [ "$WARN_COUNT" -gt 0 ]; then
        error "  Release 模式: $WARN_COUNT 个 WARN 在 release 模式下视为 FAIL"
    fi
fi

# ============================================================
# 9. Leader Jail 检查（P0-3）
# ============================================================
info "P0-3: Leader Jail..."

# 查找 hmte-leader-jail.sh
LEADER_JAIL_SCRIPT=""
if [ -f "scripts/hmte-leader-jail.sh" ]; then
    LEADER_JAIL_SCRIPT="scripts/hmte-leader-jail.sh"
elif [ -f "src/skills/hmte/scripts/hmte-leader-jail.sh" ]; then
    LEADER_JAIL_SCRIPT="src/skills/hmte/scripts/hmte-leader-jail.sh"
elif [ -f "$HOME/.hermes/profiles/default/skills/hmte/scripts/hmte-leader-jail.sh" ]; then
    LEADER_JAIL_SCRIPT="$HOME/.hermes/profiles/default/skills/hmte/scripts/hmte-leader-jail.sh"
fi

if [ -n "$LEADER_JAIL_SCRIPT" ]; then
    set +e
    bash "$LEADER_JAIL_SCRIPT" --mode "$MODE" >/dev/null 2>&1
    JAIL_EXIT=$?
    set -e

    if [ "$JAIL_EXIT" -eq 0 ]; then
        success "Leader Jail: 无违规"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        if [ "$MODE" = "release" ]; then
            error "Leader Jail: 发现越权写入 — release 模式阻断"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILURES+=("Leader Jail: forbidden writes detected (release=block)")
        else
            warn "Leader Jail: 发现越权写入 — dev 模式警告"
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
else
    if [ "$MODE" = "release" ]; then
        error "Leader Jail: hmte-leader-jail.sh 不存在 — release 模式必须执行"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("Leader Jail: script not found (required in release mode)")
    else
        warn "Leader Jail: hmte-leader-jail.sh 不存在 — 跳过"
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi

echo ""
echo "=================================================="
echo "检查完成"
echo "=================================================="
echo ""
echo "模式: $MODE"
echo "总检查项: $TOTAL_CHECKS"
echo "通过: $PASS_COUNT"
echo "失败: $FAIL_COUNT"
echo "警告: $WARN_COUNT"
echo ""

# ============================================================
# Release 模式：WARN 视为 FAIL
# ============================================================
if [ "$MODE" = "release" ] && [ "$WARN_COUNT" -gt 0 ]; then
    error "Release 模式: $WARN_COUNT 个 WARN 在 release 模式下视为 FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("Release mode: WARN_COUNT=$WARN_COUNT (WARN→FAIL)")
fi

# ============================================================
# 输出结果
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
