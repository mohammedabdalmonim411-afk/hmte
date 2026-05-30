#!/usr/bin/env bash
# hmte-lint-protocol.sh — HTE v1.4 协议检查脚本
# 扫描 .phase_control/ 和文档，验证 L01-L11 共 11 条规则
# 输出 PASS/WARN/FAIL，exit 1 当有 FAIL，否则 exit 0
#
# 约束：
#   - 只允许 bash, grep, find, python3 标准库 (json/pathlib/re)
#   - 禁止 jq, Node, npm, Python 第三方库
#   - 禁止 find ... | while read（subshell 丢计数）
#   - Python 检查用 while read < <(python3 ...) 或 python3 + 文件参数

set -euo pipefail

# ─── 颜色输出 ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}PASS${NC} $*"; }
warn()  { echo -e "  ${YELLOW}WARN${NC} $*"; }
fail()  { echo -e "  ${RED}FAIL${NC} $*"; }
rule()  { echo -e "\n${BLUE}[$1]${NC} $2"; }

# ─── 全局计数 ───────────────────────────────────────────────────────
FAIL_COUNT=0
WARN_COUNT=0

inc_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); }
inc_warn() { WARN_COUNT=$((WARN_COUNT + 1)); }

# ─── 模式 ───────────────────────────────────────────────────────────
HMTE_LINT_MODE="${HMTE_LINT_MODE:-dev}"

# ─── 根目录 ─────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="$REPO_ROOT/.phase_control"

# ─── 排除辅助函数 ──────────────────────────────────────────────────
is_excluded() {
    local f="$1"
    case "$f" in
        */.git/*)                   return 0 ;;
        */node_modules/*)           return 0 ;;
        */__pycache__/*)            return 0 ;;
        */.phase_control_archive/*) return 0 ;;
        */docs/attack-cases.md)     return 0 ;;
        *.zip)                      return 0 ;;
        *.tar.gz)                   return 0 ;;
        *_backup)                   return 0 ;;
        *_old)                      return 0 ;;
    esac
    return 1
}

# ─── 处理 python 行输出的通用函数 ──────────────────────────────────
# 将 python3 输出的 FAIL:/WARN:/PASS_FILE/PASS 行转为对应输出
# 参数: $1=rule_id, $2=prefix (可选, 如文件名)
process_output() {
    local rule_id="$1"
    local prefix="${2:-}"
    local _has_fail=false
    local _has_warn=false
    while IFS= read -r line; do
        case "$line" in
            FAIL:*)
                if [ -n "$prefix" ]; then
                    fail "$rule_id $prefix: ${line#FAIL:}"
                else
                    fail "$rule_id ${line#FAIL:}"
                fi
                _has_fail=true
                ;;
            WARN:*)
                if [ -n "$prefix" ]; then
                    warn "$rule_id $prefix: ${line#WARN:}"
                else
                    warn "$rule_id ${line#WARN:}"
                fi
                _has_warn=true
                ;;
            PASS_FILE)
                if [ -n "$prefix" ]; then
                    pass "$rule_id $prefix: 结构正确"
                else
                    pass "$rule_id: 结构正确"
                fi
                ;;
            PASS)
                if [ -n "$prefix" ]; then
                    pass "$rule_id $prefix"
                else
                    pass "$rule_id"
                fi
                ;;
        esac
    done
    if [ "$_has_fail" = true ]; then inc_fail; fi
    if [ "$_has_warn" = true ]; then inc_warn; fi
}

# ═══════════════════════════════════════════════════════════════════
# L01: phases.json 结构检查
# ═══════════════════════════════════════════════════════════════════
check_L01() {
    rule "L01" "phases.json 结构检查"
    local f="$PC/phases.json"
    if [ ! -f "$f" ]; then
        fail "L01 phases.json 不存在"
        inc_fail
        return
    fi

    local py_out
    py_out="$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
fails = []
warns = []
phases = data.get('phases')
if not isinstance(phases, list):
    fails.append('顶层 phases 不是数组')
else:
    for i, p in enumerate(phases):
        pid = p.get('phase_id') or p.get('id')
        if not pid:
            fails.append(f'phase[{i}] 缺 phase_id 和 id')
            continue
        if not p.get('phase_id'):
            warns.append(f'phase[{i}]({pid}) 只有 id 没有 phase_id')
        if not p.get('name'):
            warns.append(f'phase[{i}]({pid}) 缺 name')
        if not p.get('objective') and not p.get('description'):
            warns.append(f'phase[{i}]({pid}) 缺 objective 和 description')
        if not p.get('acceptance_criteria'):
            warns.append(f'phase[{i}]({pid}) 缺 acceptance_criteria')
        if not p.get('required_evidence'):
            warns.append(f'phase[{i}]({pid}) 缺 required_evidence')
for f_msg in fails:
    print(f'FAIL:{f_msg}')
for w_msg in warns:
    print(f'WARN:{w_msg}')
if not fails and not warns:
    print('PASS')
" "$f" 2>&1)" || {
        fail "L01 python3 执行失败"
        inc_fail
        return
    }

    local _has_fail=false
    local _has_warn=false
    while IFS= read -r line; do
        case "$line" in
            FAIL:*)
                fail "L01 ${line#FAIL:}"
                _has_fail=true
                ;;
            WARN:*)
                warn "L01 ${line#WARN:}"
                _has_warn=true
                ;;
            PASS)
                pass "L01 phases.json 结构正确"
                ;;
        esac
    done <<< "$py_out"
    if [ "$_has_fail" = true ]; then inc_fail; fi
    if [ "$_has_warn" = true ]; then inc_warn; fi
}

# ═══════════════════════════════════════════════════════════════════
# L02: session.json 结构检查
# ═══════════════════════════════════════════════════════════════════
check_L02() {
    rule "L02" "session.json 结构检查"
    local f="$PC/session.json"
    if [ ! -f "$f" ]; then
        fail "L02 session.json 不存在"
        inc_fail
        return
    fi

    local py_out
    py_out="$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
required = ['workflow', 'mode', 'task', 'status', 'created_at']
optional = ['version', 'required_first_action', 'git_head_at_kickoff',
            'git_branch_at_kickoff', 'git_dirty_at_kickoff', 'git_status_at_kickoff']
for k in required:
    if k not in data:
        print(f'FAIL:缺必需字段 {k}')
warns = []
for k in optional:
    if k not in data:
        warns.append(k)
if warns:
    print(f'WARN:缺可选字段 {chr(44).join(warns)}')
if all(k in data for k in required) and not warns:
    print('PASS')
" "$f" 2>&1)" || {
        fail "L02 python3 执行失败"
        inc_fail
        return
    }

    local _has_fail=false
    local _has_warn=false
    while IFS= read -r line; do
        case "$line" in
            FAIL:*)
                fail "L02 ${line#FAIL:}"
                _has_fail=true
                ;;
            WARN:*)
                warn "L02 ${line#WARN:}"
                _has_warn=true
                ;;
            PASS)
                pass "L02 session.json 结构正确"
                ;;
        esac
    done <<< "$py_out"
    if [ "$_has_fail" = true ]; then inc_fail; fi
    if [ "$_has_warn" = true ]; then inc_warn; fi
}

# ═══════════════════════════════════════════════════════════════════
# L03: evidence 结构检查
# ═══════════════════════════════════════════════════════════════════
L03_PY='
import json, sys, re
fname = sys.argv[1]
fpath = sys.argv[2]
pattern = r"^[a-zA-Z0-9_]+_attempt_\d+\.json$"
if not re.match(pattern, fname):
    print(f"FAIL:文件名不符合 {{phase_id}}_attempt_{{n}}.json 格式")
else:
    with open(fpath) as fh:
        data = json.load(fh)
    required = ["phase_id", "attempt", "generated_at"]
    optional = ["command_log_path", "commands_run", "changed_files"]
    optional_risk = ["unresolved_risks", "residual_risks"]
    for k in required:
        if k not in data:
            print(f"FAIL:缺必需字段 {k}")
    warns = []
    for k in optional:
        if k not in data:
            warns.append(k)
    if "unresolved_risks" not in data and "residual_risks" not in data:
        warns.append("unresolved_risks/residual_risks")
    if warns:
        print(f"WARN:缺 {chr(44).join(warns)}")
    role = data.get("role")
    if role and role not in ("worker", "release_auditor", "final_audit_executor"):
        print(f"FAIL:role={role} 不合法")
    if all(k in data for k in required) and not warns and (not role or role in ("worker", "release_auditor", "final_audit_executor")):
        print("PASS_FILE")
'

check_L03() {
    rule "L03" "evidence 结构检查"
    local evdir="$PC/evidence"
    if [ ! -d "$evdir" ]; then
        warn "L03 evidence/ 目录不存在"
        inc_warn
        return
    fi
    local file_count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$f" != *.json ]] && continue
        file_count=$((file_count + 1))
        local fname
        fname="$(basename "$f")"
        local py_out
        py_out="$(python3 -c "$L03_PY" "$fname" "$f" 2>&1)" || {
            fail "L03 $fname: python3 执行失败"
            inc_fail
            continue
        }
        local _has_fail=false
        local _has_warn=false
        while IFS= read -r line; do
            case "$line" in
                FAIL:*)
                    fail "L03 $fname: ${line#FAIL:}"
                    _has_fail=true
                    ;;
                WARN:*)
                    warn "L03 $fname: ${line#WARN:}"
                    _has_warn=true
                    ;;
                PASS_FILE)
                    pass "L03 $fname: 结构正确"
                    ;;
            esac
        done <<< "$py_out"
        if [ "$_has_fail" = true ]; then inc_fail; fi
        if [ "$_has_warn" = true ]; then inc_warn; fi
    done < <(find "$evdir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)

    if [ "$file_count" -eq 0 ]; then
        warn "L03 无 evidence JSON 文件"
        inc_warn
    fi
}

# ═══════════════════════════════════════════════════════════════════
# L04: verdict 结构检查
# ═══════════════════════════════════════════════════════════════════
L04_PY='
import json, sys, re
fname = sys.argv[1]
fpath = sys.argv[2]
pattern = r"^[a-zA-Z0-9_]+_attempt_\d+\.json$"
if not re.match(pattern, fname):
    print(f"FAIL:文件名不符合 {{phase_id}}_attempt_{{n}}.json 格式")
else:
    with open(fpath) as fh:
        data = json.load(fh)
    required = ["phase_id", "attempt", "status", "timestamp"]
    for k in required:
        if k not in data:
            print(f"FAIL:缺必需字段 {k}")
    status = data.get("status")
    if status and status not in ("PASS", "FAIL", "BLOCK"):
        print(f"FAIL:status={status} 不合法，只能是 PASS/FAIL/BLOCK")
    if "decision" in data:
        print("WARN:出现 legacy 字段 decision")
    if status == "PASS":
        scorecard = data.get("adversarial_scorecard")
        if not scorecard:
            print("FAIL:PASS verdict 缺 adversarial_scorecard")
        cf_top = data.get("criteria_failed")
        cf_sc = scorecard.get("criteria_failed") if scorecard else None
        ep_top = data.get("evidence_paths")
        ep_sc = scorecard.get("evidence_paths") if scorecard else None
        cf = cf_top if cf_top is not None else cf_sc
        ep = ep_top if ep_top is not None else ep_sc
        if cf is not None and len(cf) > 0:
            print("FAIL:PASS verdict 但 criteria_failed 非空")
        if ep is not None and len(ep) == 0:
            print("FAIL:PASS verdict 但 evidence_paths 为空")
        elif ep is None:
            print("FAIL:PASS verdict 缺 evidence_paths")
    if all(k in data for k in required) and status in ("PASS", "FAIL", "BLOCK") and "decision" not in data:
        if status != "PASS":
            print("PASS_FILE")
'

check_L04() {
    rule "L04" "verdict 结构检查"
    local vdir="$PC/verdicts"
    if [ ! -d "$vdir" ]; then
        warn "L04 verdicts/ 目录不存在"
        inc_warn
        return
    fi
    local file_count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$f" != *.json ]] && continue
        file_count=$((file_count + 1))
        local fname
        fname="$(basename "$f")"
        local py_out
        py_out="$(python3 -c "$L04_PY" "$fname" "$f" 2>&1)" || {
            fail "L04 $fname: python3 执行失败"
            inc_fail
            continue
        }
        local _has_fail=false
        local _has_warn=false
        while IFS= read -r line; do
            case "$line" in
                FAIL:*)
                    fail "L04 $fname: ${line#FAIL:}"
                    _has_fail=true
                    ;;
                WARN:*)
                    warn "L04 $fname: ${line#WARN:}"
                    _has_warn=true
                    ;;
                PASS_FILE)
                    pass "L04 $fname: 结构正确"
                    ;;
            esac
        done <<< "$py_out"
        if [ "$_has_fail" = true ]; then inc_fail; fi
        if [ "$_has_warn" = true ]; then inc_warn; fi
    done < <(find "$vdir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)

    if [ "$file_count" -eq 0 ]; then
        warn "L04 无 verdict JSON 文件"
        inc_warn
    fi
}

# ═══════════════════════════════════════════════════════════════════
# L05: delegation receipt 结构检查
# ═══════════════════════════════════════════════════════════════════
L05_PY='
import json, sys, re
fname = sys.argv[1]
fpath = sys.argv[2]
pattern = r"^[a-zA-Z0-9_]+_attempt_\d+_(worker|verifier)\.json$"
if not re.match(pattern, fname):
    print(f"FAIL:文件名不符合 {{phase_id}}_attempt_{{n}}_{{worker|verifier}}.json 格式")
else:
    with open(fpath) as fh:
        data = json.load(fh)
    required = ["phase_id", "attempt", "role", "created_at"]
    for k in required:
        if k not in data:
            print(f"FAIL:缺必需字段 {k}")
    tl = data.get("delegation_trust_level") or data.get("trust_level")
    if tl and tl not in ("INTENT_ONLY", "OBSERVED", "NONE"):
        print(f"FAIL:trust_level={tl} 不合法")
    role = data.get("role")
    if role and role not in ("worker", "verifier"):
        print(f"FAIL:role={role} 不合法，只允许 worker/verifier")
    warns = []
    for k in ["delegation_method", "leader_instruction_path", "expected_output_path"]:
        if k not in data:
            warns.append(k)
    if warns:
        print(f"WARN:缺 {chr(44).join(warns)}")
    eop = data.get("expected_output_path", "")
    if role == "worker" and eop and not eop.startswith(".phase_control/evidence/"):
        print("FAIL:role=worker 时 expected_output_path 必须 startswith .phase_control/evidence/")
    if role == "verifier" and eop and not eop.startswith(".phase_control/verdicts/"):
        print("FAIL:role=verifier 时 expected_output_path 必须 startswith .phase_control/verdicts/")
    if all(k in data for k in required) and tl in ("INTENT_ONLY", "OBSERVED", "NONE") and role in ("worker", "verifier") and not warns:
        print("PASS_FILE")
'

check_L05() {
    rule "L05" "delegation receipt 结构检查"
    local ddir="$PC/delegations"
    if [ ! -d "$ddir" ]; then
        warn "L05 delegations/ 目录不存在"
        inc_warn
        return
    fi
    local file_count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$f" != *.json ]] && continue
        file_count=$((file_count + 1))
        local fname
        fname="$(basename "$f")"
        local py_out
        py_out="$(python3 -c "$L05_PY" "$fname" "$f" 2>&1)" || {
            fail "L05 $fname: python3 执行失败"
            inc_fail
            continue
        }
        local _has_fail=false
        local _has_warn=false
        while IFS= read -r line; do
            case "$line" in
                FAIL:*)
                    fail "L05 $fname: ${line#FAIL:}"
                    _has_fail=true
                    ;;
                WARN:*)
                    warn "L05 $fname: ${line#WARN:}"
                    _has_warn=true
                    ;;
                PASS_FILE)
                    pass "L05 $fname: 结构正确"
                    ;;
            esac
        done <<< "$py_out"
        if [ "$_has_fail" = true ]; then inc_fail; fi
        if [ "$_has_warn" = true ]; then inc_warn; fi
    done < <(find "$ddir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)

    if [ "$file_count" -eq 0 ]; then
        warn "L05 无 delegation JSON 文件"
        inc_warn
    fi
}

# ═══════════════════════════════════════════════════════════════════
# L06a: command log 结构检查
# ═══════════════════════════════════════════════════════════════════
L06A_PY='
import json, sys
fpath = sys.argv[1]
required_fields = ["phase_id", "attempt", "command", "exit_code", "runner", "started_at", "ended_at", "output_tail"]
has_fail = False
has_warn = False
line_num = 0
with open(fpath) as fh:
    for raw_line in fh:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        line_num += 1
        try:
            data = json.loads(raw_line)
        except json.JSONDecodeError:
            print(f"FAIL:第 {line_num} 行 JSON 解析失败")
            has_fail = True
            continue
        for k in required_fields:
            if k not in data:
                print(f"FAIL:第 {line_num} 行缺字段 {k}")
                has_fail = True
        runner = data.get("runner")
        if runner is None:
            print(f"FAIL:第 {line_num} 行缺 runner")
            has_fail = True
        elif runner != "hmte exec":
            print(f"WARN:第 {line_num} 行 runner={runner} 不是 hmte exec")
            has_warn = True
if not has_fail and not has_warn:
    print("PASS_FILE")
'

check_L06a() {
    rule "L06a" "command log 结构检查"
    local ldir="$PC/logs"
    if [ ! -d "$ldir" ]; then
        warn "L06a logs/ 目录不存在"
        inc_warn
        return
    fi
    local file_count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$f" == *.commands.jsonl ]] || continue
        file_count=$((file_count + 1))
        local fname
        fname="$(basename "$f")"
        local py_out
        py_out="$(python3 -c "$L06A_PY" "$f" 2>&1)" || {
            fail "L06a $fname: python3 执行失败"
            inc_fail
            continue
        }
        local _has_fail=false
        local _has_warn=false
        while IFS= read -r line; do
            case "$line" in
                FAIL:*)
                    fail "L06a $fname: ${line#FAIL:}"
                    _has_fail=true
                    ;;
                WARN:*)
                    warn "L06a $fname: ${line#WARN:}"
                    _has_warn=true
                    ;;
                PASS_FILE)
                    pass "L06a $fname: 结构正确"
                    ;;
            esac
        done <<< "$py_out"
        if [ "$_has_fail" = true ]; then inc_fail; fi
        if [ "$_has_warn" = true ]; then inc_warn; fi
    done < <(find "$ldir" -maxdepth 1 -type f -name '*.commands.jsonl' 2>/dev/null)

    if [ "$file_count" -eq 0 ]; then
        warn "L06a 无 .commands.jsonl 文件"
        inc_warn
    fi
}

# ═══════════════════════════════════════════════════════════════════
# L06b: 文档示例检查
# ═══════════════════════════════════════════════════════════════════
collect_doc_files() {
    DOC_FILES=()
    local patterns=(
        "$REPO_ROOT/README.md"
        "$REPO_ROOT/HERMES.md"
        "$REPO_ROOT/src/skills/hmte/SKILL.md"
    )
    for f in "${patterns[@]}"; do
        [ -f "$f" ] && DOC_FILES+=("$f")
    done
    if [ -d "$REPO_ROOT/docs" ]; then
        while IFS= read -r f; do
            DOC_FILES+=("$f")
        done < <(find "$REPO_ROOT/docs" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
    fi
    if [ -d "$REPO_ROOT/src" ]; then
        while IFS= read -r f; do
            DOC_FILES+=("$f")
        done < <(find "$REPO_ROOT/src" -name '*.md' -type f 2>/dev/null)
    fi
    local filtered=()
    for f in "${DOC_FILES[@]}"; do
        is_excluded "$f" && continue
        # Deduplicate: skip if already in filtered
        local _dup=false
        for _existing in "${filtered[@]+"${filtered[@]}"}"; do
            [ "$_existing" = "$f" ] && _dup=true && break
        done
        [ "$_dup" = false ] && filtered+=("$f")
    done
    DOC_FILES=("${filtered[@]}")
}

check_L06b() {
    rule "L06b" "文档示例检查"
    collect_doc_files
    if [ ${#DOC_FILES[@]} -eq 0 ]; then
        warn "L06b 无文档文件可扫描"
        inc_warn
        return
    fi
    local _has_warn=false
    local found_any=false
    for f in "${DOC_FILES[@]}"; do
        is_excluded "$f" && continue
        local fname
        fname="$(basename "$f")"
        if grep -q 'hmte exec\|bash scripts/hmte-exec\.sh' "$f" 2>/dev/null; then
            found_any=true
            if ! grep -q '\-\-attempt' "$f" 2>/dev/null; then
                warn "L06b $fname: 包含 hmte exec 示例但缺 --attempt"
                _has_warn=true
            else
                pass "L06b $fname: 包含 hmte exec 示例且有 --attempt"
            fi
        fi
    done
    if [ "$found_any" = false ]; then
        warn "L06b 未找到 hmte exec 或 hmte-exec.sh 示例"
        _has_warn=true
    fi
    if [ "$_has_warn" = true ]; then inc_warn; fi
}

# ═══════════════════════════════════════════════════════════════════
# L07: instruction 文件命名检查
# ═══════════════════════════════════════════════════════════════════
L07_PY='
import re, sys
fname = sys.argv[1]
valid_leader = fname == "leader_kickoff.json"
valid_worker = bool(re.match(r"^[a-zA-Z0-9_]+_attempt_\d+_worker\.json$", fname))
valid_verifier = bool(re.match(r"^[a-zA-Z0-9_]+_attempt_\d+_verifier\.json$", fname))
forbidden_patterns = [
    r"_worker_0\.json$",
    r"_verifier_0\.json$",
    r"^instruction_.*\.md$",
    r"_instruction\.md$",
    r"^phase-1-worker\.json$",
    r"^phase-1-attempt-1\.json$",
]
for pat in forbidden_patterns:
    if re.search(pat, fname):
        print(f"FAIL:命中禁止格式 {pat}")
        sys.exit(0)
if valid_leader or valid_worker or valid_verifier:
    print("PASS_FILE")
else:
    print(f"FAIL:不符合任何合法格式")
'

check_L07() {
    rule "L07" "instruction 文件命名检查"
    local idir="$PC/instructions"
    if [ ! -d "$idir" ]; then
        warn "L07 instructions/ 目录不存在"
        inc_warn
        return
    fi
    local file_count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$f" == *.json ]] || continue
        file_count=$((file_count + 1))
        local fname
        fname="$(basename "$f")"
        local py_out
        py_out="$(python3 -c "$L07_PY" "$fname" 2>&1)" || {
            fail "L07 $fname: python3 执行失败"
            inc_fail
            continue
        }
        local _has_fail=false
        local _has_warn=false
        while IFS= read -r line; do
            case "$line" in
                FAIL:*)
                    fail "L07 $fname: ${line#FAIL:}"
                    _has_fail=true
                    ;;
                PASS_FILE)
                    pass "L07 $fname: 命名合法"
                    ;;
            esac
        done <<< "$py_out"
        if [ "$_has_fail" = true ]; then inc_fail; fi
    done < <(find "$idir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)

    if [ "$file_count" -eq 0 ]; then
        warn "L07 无 instruction JSON 文件"
        inc_warn
    fi
}

# ═══════════════════════════════════════════════════════════════════
# L08: final_audit 文件名检查
# ═══════════════════════════════════════════════════════════════════
L08_PY='
import re, sys
rel = sys.argv[1]
valid_evidence = bool(re.match(r"^evidence/final_audit_attempt_\d+\.json$", rel))
valid_verdict = bool(re.match(r"^verdicts/final_audit_attempt_\d+\.json$", rel))
valid_log = bool(re.match(r"^logs/final_audit_attempt_\d+\.commands\.jsonl$", rel))
forbidden_patterns = [
    r"final-audit",
    r"final_audit_attempt_\d+\.evidence\.json",
    r"final_audit_attempt_\d+\.verdict\.json",
    r"final_audit\.json",
    r"final_audit_.*\.md",
]
for pat in forbidden_patterns:
    if re.search(pat, rel):
        print(f"FAIL:命中禁止格式 {pat}")
        sys.exit(0)
if valid_evidence or valid_verdict or valid_log:
    print("PASS_FILE")
'

check_L08() {
    rule "L08" "final_audit 文件名检查"
    if [ ! -d "$PC" ]; then
        warn "L08 .phase_control/ 不存在"
        inc_warn
        return
    fi
    local found_any=false
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$(basename "$f")" == ".gitkeep" ]] && continue
        if [[ "$f" == */src/skills/hmte/final-audit-template.md ]]; then
            continue
        fi
        found_any=true
        local rel
        rel="${f#$PC/}"
        local py_out
        py_out="$(python3 -c "$L08_PY" "$rel" 2>&1)" || {
            fail "L08 $rel: python3 执行失败"
            inc_fail
            continue
        }
        local _has_fail=false
        while IFS= read -r line; do
            case "$line" in
                FAIL:*)
                    fail "L08 $rel: ${line#FAIL:}"
                    _has_fail=true
                    ;;
                PASS_FILE)
                    pass "L08 $rel: 命名合法"
                    ;;
            esac
        done <<< "$py_out"
        if [ "$_has_fail" = true ]; then inc_fail; fi
    done < <(find "$PC" -type f \( -name '*final_audit*' -o -name '*final-audit*' \) 2>/dev/null)

    if [ "$found_any" = false ]; then
        pass "L08 无 final_audit 相关文件"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# L09: 时间字段按文件类型检查
# ═══════════════════════════════════════════════════════════════════
check_L09() {
    rule "L09" "时间字段按文件类型检查"
    if [ ! -d "$PC" ]; then
        warn "L09 .phase_control/ 不存在"
        inc_warn
        return
    fi
    local _has_fail=false
    local _has_warn=false
    local file_count=0

    # evidence/*.json → generated_at
    if [ -d "$PC/evidence" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [[ "$f" != *.json ]] && continue
            file_count=$((file_count + 1))
            local fname
            fname="$(basename "$f")"
            if ! grep -q '"generated_at"' "$f" 2>/dev/null; then
                fail "L09 evidence/$fname: 缺 generated_at"
                _has_fail=true
            else
                pass "L09 evidence/$fname: 有 generated_at"
            fi
        done < <(find "$PC/evidence" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
    fi

    # verdicts/*.json → timestamp
    if [ -d "$PC/verdicts" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [[ "$f" != *.json ]] && continue
            file_count=$((file_count + 1))
            local fname
            fname="$(basename "$f")"
            if ! grep -q '"timestamp"' "$f" 2>/dev/null; then
                fail "L09 verdicts/$fname: 缺 timestamp"
                _has_fail=true
            else
                pass "L09 verdicts/$fname: 有 timestamp"
            fi
        done < <(find "$PC/verdicts" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
    fi

    # delegations/*.json → created_at
    if [ -d "$PC/delegations" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [[ "$f" != *.json ]] && continue
            file_count=$((file_count + 1))
            local fname
            fname="$(basename "$f")"
            if ! grep -q '"created_at"' "$f" 2>/dev/null; then
                fail "L09 delegations/$fname: 缺 created_at"
                _has_fail=true
            else
                pass "L09 delegations/$fname: 有 created_at"
            fi
        done < <(find "$PC/delegations" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
    fi

    # instructions/*.json → created_at
    if [ -d "$PC/instructions" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [[ "$f" != *.json ]] && continue
            file_count=$((file_count + 1))
            local fname
            fname="$(basename "$f")"
            if ! grep -q '"created_at"' "$f" 2>/dev/null; then
                fail "L09 instructions/$fname: 缺 created_at"
                _has_fail=true
            else
                pass "L09 instructions/$fname: 有 created_at"
            fi
        done < <(find "$PC/instructions" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
    fi

    # session.json → created_at
    if [ -f "$PC/session.json" ]; then
        file_count=$((file_count + 1))
        if ! grep -q '"created_at"' "$PC/session.json" 2>/dev/null; then
            fail "L09 session.json: 缺 created_at"
            _has_fail=true
        else
            pass "L09 session.json: 有 created_at"
        fi
    fi

    # state.json → updated_at
    if [ -f "$PC/state.json" ]; then
        file_count=$((file_count + 1))
        if ! grep -q '"updated_at"' "$PC/state.json" 2>/dev/null; then
            fail "L09 state.json: 缺 updated_at"
            _has_fail=true
        else
            pass "L09 state.json: 有 updated_at"
        fi
    fi

    # logs/*.commands.jsonl → started_at / ended_at
    if [ -d "$PC/logs" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [[ "$f" == *.commands.jsonl ]] || continue
            file_count=$((file_count + 1))
            local fname
            fname="$(basename "$f")"
            local missing=false
            if ! grep -q '"started_at"' "$f" 2>/dev/null; then
                fail "L09 logs/$fname: 缺 started_at"
                _has_fail=true
                missing=true
            fi
            if ! grep -q '"ended_at"' "$f" 2>/dev/null; then
                fail "L09 logs/$fname: 缺 ended_at"
                _has_fail=true
                missing=true
            fi
            if [ "$missing" = false ]; then
                pass "L09 logs/$fname: 有 started_at 和 ended_at"
            fi
        done < <(find "$PC/logs" -maxdepth 1 -type f -name '*.commands.jsonl' 2>/dev/null)
    fi

    if [ "$file_count" -eq 0 ]; then
        warn "L09 无可检查的文件"
        _has_warn=true
    fi
    if [ "$_has_fail" = true ]; then inc_fail; fi
    if [ "$_has_warn" = true ]; then inc_warn; fi
}

# ═══════════════════════════════════════════════════════════════════
# L10: OBSERVED 委派检查
# ═══════════════════════════════════════════════════════════════════
L10_PY='
import json, sys
fpath = sys.argv[1]
with open(fpath) as fh:
    data = json.load(fh)
tl = data.get("delegation_trust_level") or data.get("trust_level")
if tl != "OBSERVED":
    print("NOT_OBSERVED")
    sys.exit(0)
fails = []
tcp = data.get("tool_call_trace_path", "")
odtid = data.get("observed_delegate_task_id", "")
clp = data.get("command_log_path", "")
ep = data.get("evidence_paths", [])
if not tcp:
    fails.append("缺 tool_call_trace_path")
if not odtid:
    fails.append("缺 observed_delegate_task_id")
if tcp and clp and tcp == clp:
    fails.append("tool_call_trace_path 不能等于 command_log_path")
if tcp and tcp in ep:
    fails.append("tool_call_trace_path 不能出现在 evidence_paths 中")
for f_msg in fails:
    print(f"FAIL:{f_msg}")
if not fails:
    print("PASS_FILE")
# 输出 tool_call_trace_path 用于文件存在性检查
if tcp:
    print(f"TRACE_PATH:{tcp}")
'

check_L10() {
    rule "L10" "OBSERVED 委派检查"
    local ddir="$PC/delegations"
    if [ ! -d "$ddir" ]; then
        warn "L10 delegations/ 目录不存在"
        inc_warn
        return
    fi
    local _has_fail=false
    local found_observed=false
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [[ "$f" != *.json ]] && continue
        local fname
        fname="$(basename "$f")"
        local py_out
        py_out="$(python3 -c "$L10_PY" "$f" 2>&1)" || {
            fail "L10 $fname: python3 执行失败"
            _has_fail=true
            continue
        }
        local trace_path=""
        local _file_has_fail=false
        while IFS= read -r line; do
            case "$line" in
                NOT_OBSERVED)
                    ;;
                TRACE_PATH:*)
                    trace_path="${line#TRACE_PATH:}"
                    ;;
                FAIL:*)
                    fail "L10 $fname: ${line#FAIL:}"
                    _has_fail=true
                    _file_has_fail=true
                    ;;
                PASS_FILE)
                    pass "L10 $fname: OBSERVED 委派完整"
                    found_observed=true
                    ;;
            esac
        done <<< "$py_out"
        # 检查 tool_call_trace_path 文件存在性
        if [ -n "$trace_path" ] && [ "$_file_has_fail" = false ]; then
            if [ ! -f "$REPO_ROOT/$trace_path" ]; then
                fail "L10 $fname: tool_call_trace_path=$trace_path 文件不存在"
                _has_fail=true
                found_observed=true
            fi
        fi
    done < <(find "$ddir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)

    if [ "$found_observed" = false ]; then
        pass "L10 无 OBSERVED 委派记录"
    fi
    if [ "$_has_fail" = true ]; then inc_fail; fi
}

# ═══════════════════════════════════════════════════════════════════
# L11: team-rules 存在性检查
# ═══════════════════════════════════════════════════════════════════
check_L11() {
    rule "L11" "team-rules 存在性检查"
    local tr="$REPO_ROOT/.hmte/team-rules.md"
    if [ -f "$tr" ]; then
        pass "L11 .hmte/team-rules.md 存在"
        return
    fi
    if [ "$HMTE_LINT_MODE" = "release" ]; then
        fail "L11 .hmte/team-rules.md 不存在 (release 模式)"
        inc_fail
    else
        warn "L11 .hmte/team-rules.md 不存在 (dev 模式)"
        inc_warn
    fi
}

# ═══════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " HTE v1.4 协议检查 (mode=$HMTE_LINT_MODE)"
echo " 项目根目录: $REPO_ROOT"
echo "═══════════════════════════════════════════════════════════"

check_L01
check_L02
check_L03
check_L04
check_L05
check_L06a
check_L06b
check_L07
check_L08
check_L09
check_L10
check_L11

echo ""
echo "═══════════════════════════════════════════════════════════"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e " ${RED}结果: FAIL_COUNT=$FAIL_COUNT, WARN_COUNT=$WARN_COUNT${NC}"
    echo "═══════════════════════════════════════════════════════════"
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo -e " ${YELLOW}结果: WARN_COUNT=$WARN_COUNT (无 FAIL)${NC}"
    echo "═══════════════════════════════════════════════════════════"
    exit 0
else
    echo -e " ${GREEN}结果: 全部通过${NC}"
    echo "═══════════════════════════════════════════════════════════"
    exit 0
fi
