#!/usr/bin/env bash
# hmte-plan-contract.sh - Plan Contract 验证和 canonical JSON 生成
# Version: 2.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 默认值
ACTION="validate"
PLAN_PATH=""
CANONICAL_PATH=""
GENERATE_CANONICAL=false

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Plan Contract 验证和 canonical JSON 生成工具

OPTIONS:
    --plan PATH              Plan Contract Markdown 文件路径
    --canonical PATH         Canonical JSON 文件路径
    --generate-canonical     生成 canonical JSON
    --validate               验证 Plan Contract（默认）
    -h, --help               显示帮助

EXAMPLES:
    # 验证 Plan Contract
    $0 --plan HTE_v2.0_PROJECT_PLAN.md

    # 生成 canonical JSON
    $0 --plan HTE_v2.0_PROJECT_PLAN.md --generate-canonical

    # 验证 canonical JSON
    $0 --canonical plan_contract.json --validate

EOF
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --plan)
            PLAN_PATH="$2"
            shift 2
            ;;
        --canonical)
            CANONICAL_PATH="$2"
            shift 2
            ;;
        --generate-canonical)
            GENERATE_CANONICAL=true
            shift
            ;;
        --validate)
            ACTION="validate"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# 验证 Plan Contract Markdown
validate_plan_markdown() {
    local plan_path="$1"
    
    if [[ ! -f "$plan_path" ]]; then
        echo -e "${RED}❌ Plan Contract 文件不存在: $plan_path${NC}"
        return 1
    fi
    
    echo "Validating Plan Contract: $plan_path"
    echo ""
    
    local errors=0
    local warnings=0
    
    # 检查 1: Plan ID 存在
    if ! grep -q "^\*\*Plan ID\*\*:" "$plan_path"; then
        echo -e "${RED}❌ 缺少 Plan ID${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✅ Plan ID 存在${NC}"
    fi
    
    # 检查 2: Version 存在
    if ! grep -q "^\*\*Version\*\*:" "$plan_path"; then
        echo -e "${RED}❌ 缺少 Version${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✅ Version 存在${NC}"
    fi
    
    # 检查 3: Status 存在
    if ! grep -q "^\\*\\*Status\\*\\*:" "$plan_path"; then
        echo -e "${RED}❌ 缺少 Status${NC}"
        ((errors++))
    else
        local status=""
        status=$(grep "^\\*\\*Status\\*\\*:" "$plan_path" | sed "s/.*Status\\*\\*: *//" | tr -d "\r" | head -1 | xargs || echo "")
        if [[ -z "$status" ]]; then
            echo -e "${YELLOW}⚠️  Status 为空${NC}"
            ((warnings++))
        elif [[ ! "$status" =~ ^(draft|locked|amended|Planning)$ ]]; then
            echo -e "${YELLOW}⚠️  Status 不是标准值: $status（允许: draft, locked, amended）${NC}"
            ((warnings++))
        else
            echo -e "${GREEN}✅ Status 有效: $status${NC}"
        fi
    fi
    
    # 检查 4: Scope 章节存在
    if ! grep -q "^## .*Scope" "$plan_path"; then
        echo -e "${RED}❌ 缺少 Scope 章节${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✅ Scope 章节存在${NC}"
    fi
    
    # 检查 5: ID 格式检查（抽样）
    local invalid_ids=0
    local empty_ids=0
    local in_table=false
    while IFS= read -r line; do
        # 检测表格开始（表头后的分隔行）
        if [[ "$line" =~ ^\|[[:space:]]*-+[[:space:]]*\| ]]; then
            in_table=true
            continue
        fi
        
        # 检测表格结束（空行或非表格行）
        if [[ -z "$line" ]] || [[ ! "$line" =~ ^\| ]]; then
            in_table=false
            continue
        fi
        
        # 如果在表格内，检查第一列 ID
        if [[ "$in_table" == true ]]; then
            # 提取第一列（ID 列）
            local first_col
            first_col=$(echo "$line" | cut -d'|' -f2 | xargs)
            
            # 检查是否为空
            if [[ -z "$first_col" ]]; then
                echo -e "${RED}❌ 发现空 ID（表格第一列为空）${NC}"
                ((errors++))
                ((empty_ids++))
                if [[ $empty_ids -ge 3 ]]; then
                    echo -e "${RED}❌ 发现多个空 ID，停止检查${NC}"
                    break
                fi
                continue
            fi
            
            # 检查 ID 格式
            if [[ "$first_col" =~ ^(S-[0-9]+|NS-[0-9]+|P-[0-9]+|AC-[0-9]+|T-[0-9]+|NT-[0-9]+|A-[0-9]+|F-[0-9]+|R-[0-9]+|D-[0-9]+|RC-[0-9]+|SC-[0-9]+)$ ]]; then
                local id="$first_col"
                # 检查是否是 3 位数字（放宽要求，1-3 位都接受）
                if [[ ! "$id" =~ ^[A-Z]+-[0-9]{1,3}$ ]]; then
                    echo -e "${YELLOW}⚠️  ID 格式不规范: $id（建议 3 位数字零填充）${NC}"
                    ((warnings++))
                    ((invalid_ids++))
                    if [[ $invalid_ids -ge 5 ]]; then
                        echo -e "${YELLOW}⚠️  发现多个 ID 格式问题，仅显示前 5 个${NC}"
                        break
                    fi
                fi
            fi
        fi
    done < "$plan_path"
    
    if [[ $empty_ids -eq 0 ]] && [[ $invalid_ids -eq 0 ]]; then
        echo -e "${GREEN}✅ ID 格式检查通过${NC}"
    fi
    
    # 检查 6: 模糊词检测（强制性，阻断 P0）
    local vague_words=(
        # 中文模糊词
        "实现所有核心功能"
        "完成相关优化"
        "基本达成"
        "适当处理"
        "视情况验证"
        "后续完善"
        "改进系统"
        "优化性能"
        "提升质量"
        # 英文模糊词
        "improve system"
        "make it better"
        "optimize"
        "enhance"
        "all good"
        "core functionality"
        "basic implementation"
        "appropriate handling"
        "later"
        "TBD"
        "TODO"
        "fix issues"
        "handle edge cases"
    )
    
    local found_vague=false
    local vague_count=0
    for word in "${vague_words[@]}"; do
        if grep -iq "$word" "$plan_path"; then
            if [[ "$found_vague" == false ]]; then
                echo -e "${RED}✗ 发现模糊描述（vague descriptions）：${NC}"
                found_vague=true
            fi
            echo -e "${RED}   - $word${NC}"
            ((errors++))
            ((vague_count++))
            if [[ $vague_count -ge 5 ]]; then
                echo -e "${RED}✗ 模糊描述过多，停止检查（已发现 $vague_count 处）${NC}"
                break
            fi
        fi
    done
    
    if [[ "$found_vague" == false ]]; then
        echo -e "${GREEN}✓ Plan items are具体且可验证${NC}"
    else
        echo -e "${RED}✗ Plan Contract 必须具体、可验证、可测试${NC}"
        echo -e "${RED}   请将模糊描述改为明确的任务和验收标准${NC}"
    fi
    
    # 检查 7: Required Tests 章节
    if ! grep -q "^## .*Required Tests" "$plan_path" && ! grep -q "^### .*Required Tests" "$plan_path"; then
        echo -e "${YELLOW}⚠️  缺少 Required Tests 章节${NC}"
        ((warnings++))
    else
        echo -e "${GREEN}✅ Required Tests 章节存在${NC}"
    fi
    
    # 检查 8: Acceptance Criteria 章节
    if ! grep -q "^## .*Acceptance Criteria" "$plan_path" && ! grep -q "^### .*Acceptance Criteria" "$plan_path" && ! grep -q "^#### .*验收标准" "$plan_path"; then
        echo -e "${YELLOW}⚠️  缺少 Acceptance Criteria 章节${NC}"
        ((warnings++))
    else
        echo -e "${GREEN}✅ Acceptance Criteria 章节存在${NC}"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo " 结果: ERRORS=$errors, WARNINGS=$warnings"
    echo "═══════════════════════════════════════════════════════════"
    
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}❌ Plan Contract 验证失败${NC}"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Plan Contract 验证通过（有警告）${NC}"
        return 0
    else
        echo -e "${GREEN}✅ Plan Contract 验证通过${NC}"
        return 0
    fi
}

# 生成 canonical JSON（简化版）
generate_canonical_json() {
    local plan_path="$1"
    
    if [[ ! -f "$plan_path" ]]; then
        echo -e "${RED}❌ Plan Contract 文件不存在: $plan_path${NC}"
        return 1
    fi
    
    echo "Generating canonical JSON from: $plan_path"
    
    # 提取 Plan ID
    local plan_id
    plan_id=$(grep "^\*\*Plan ID\*\*:" "$plan_path" | sed "s/.*Plan ID\*\*: *//" | tr -d "\r" | xargs || echo "UNKNOWN")
    
    # 提取 Version
    local version
    version=$(grep "^\*\*Version\*\*:" "$plan_path" | sed "s/.*Version\*\*: *//" | tr -d "\r" | xargs || echo "1.0")
    
    # 提取 Project
    local project
    project=$(grep "^\*\*Project\*\*:" "$plan_path" | sed "s/.*Project\*\*: *//" | tr -d "\r" | xargs || echo "UNKNOWN")
    
    # 提取 Status
    local status
    status=$(grep "^\*\*Status\*\*:" "$plan_path" | sed "s/.*Status\*\*: *//" | tr -d "\r" | xargs || echo "draft")
    
    # 生成 canonical JSON
    cat > "${plan_path%.md}_canonical.json" << EOF
{
  "plan_id": "$plan_id",
  "version": "$version",
  "project": "$project",
  "status": "$status",
  "scope": [],
  "non_scope": [],
  "phases": [],
  "acceptance_criteria": [],
  "required_tests": [],
  "required_negative_tests": [],
  "allowed_files": [],
  "forbidden_files": [],
  "risk_register": [],
  "dogfood_requirements": [],
  "release_conditions": [],
  "stop_conditions": []
}
EOF
    
    echo -e "${GREEN}✅ Canonical JSON 已生成: ${plan_path%.md}_canonical.json${NC}"
    echo ""
    echo "注意: 这是简化版 canonical JSON，仅包含元数据。"
    echo "完整解析需要更复杂的 Markdown 表格解析逻辑。"
    
    return 0
}

# 验证 canonical JSON
validate_canonical_json() {
    local canonical_path="$1"
    
    if [[ ! -f "$canonical_path" ]]; then
        echo -e "${RED}❌ Canonical JSON 文件不存在: $canonical_path${NC}"
        return 1
    fi
    
    echo "Validating canonical JSON: $canonical_path"
    echo ""
    
    # 检查 JSON 格式
    if ! python3 -m json.tool "$canonical_path" > /dev/null 2>&1; then
        echo -e "${RED}❌ JSON 格式无效${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ JSON 格式有效${NC}"
    
    # 检查必需字段
    local required_fields=(
        "plan_id"
        "version"
        "project"
        "status"
        "scope"
        "non_scope"
        "phases"
        "acceptance_criteria"
    )
    
    local errors=0
    for field in "${required_fields[@]}"; do
        if ! grep -q "\"$field\":" "$canonical_path"; then
            echo -e "${RED}❌ 缺少必需字段: $field${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✅ 必需字段存在: $field${NC}"
        fi
    done
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}❌ Canonical JSON 验证失败${NC}"
        return 1
    else
        echo -e "${GREEN}✅ Canonical JSON 验证通过${NC}"
        return 0
    fi
}

# 主逻辑
main() {
    if [[ -n "$PLAN_PATH" ]]; then
        if [[ "$GENERATE_CANONICAL" == true ]]; then
            generate_canonical_json "$PLAN_PATH"
        else
            validate_plan_markdown "$PLAN_PATH"
        fi
    elif [[ -n "$CANONICAL_PATH" ]]; then
        validate_canonical_json "$CANONICAL_PATH"
    else
        echo -e "${RED}❌ 必须指定 --plan 或 --canonical${NC}"
        usage
    fi
}

main
