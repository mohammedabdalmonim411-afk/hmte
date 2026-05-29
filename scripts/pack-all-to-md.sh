#!/usr/bin/env bash
# pack-all-to-md.sh
# 将项目所有核心文件打包 — 支持 tar.gz（默认）和 Markdown 两种模式
# 更新: 2026-05-28 — 增加 tar.gz 默认模式
#
# 用法:
#   pack-all-to-md.sh              # 默认 tar.gz 模式
#   pack-all-to-md.sh --markdown   # 旧的 Markdown 打包模式
#   pack-all-to-md.sh --markdown output.md  # 指定输出文件

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- 模式判断 ---
MODE="tar"
OUTPUT_FILE=""

for arg in "$@"; do
    case "$arg" in
        --markdown)
            MODE="md"
            ;;
        *)
            OUTPUT_FILE="$arg"
            ;;
    esac
done

# --- 定义要打包的文件列表（按重要性排序）---
declare -a FILES=(
    # === 核心配置 ===
    "README.md"
    "HERMES.md"
    "CONTRIBUTING.md"
    "CHANGELOG.md"

    # === Agent定义 ===
    "src/agents/master-planner.md"
    "src/agents/phase-executor.md"
    "src/agents/verifier.md"

    # === Skill定义 ===
    "src/skills/hmte/SKILL.md"
    "src/skills/hmte/phase-template.md"
    "src/skills/hmte/audit-checklist.md"
    "src/skills/hmte/evidence-schema.json"

    # === Anti-Fake Enforcement (新增 v2.5) ===
    "src/skills/hmte/delegation-receipt-schema.json"
    "src/skills/hmte/verdict-schema.json"
    "src/skills/hmte/scripts/hmte-audit-flow.py"

    # === Orchestrator ===
    "src/skills/hmte/scripts/orchestrator.py"

    # === 核心脚本 ===
    "src/skills/hmte/scripts/write_state.py"
    "src/skills/hmte/scripts/collect_evidence.sh"
    "src/skills/hmte/scripts/phase_gate.sh"

    # === Hooks ===
    "src/skills/hmte/hooks/pretool_guard.sh"
    "src/skills/hmte/hooks/stop_gate.sh"
    "src/skills/hmte/hooks/task_naming.sh"

    # === 用户脚本 ===
    "scripts/hmte"
    "scripts/hmte-run.sh"
    "scripts/hmte-start.sh"
    "scripts/hmte-stop.sh"
    "scripts/hmte-status.sh"
    "scripts/hmte-e2e.sh"
    "scripts/hmte-exec.sh"
    "scripts/hmte-init.sh"
    "scripts/hmte-doctor.sh"
    "scripts/hmte-write-receipt.sh"
    "scripts/e2e-anti-fake-test.sh"

    # === 安装脚本 ===
    "install-to-hermes.sh"

    # === HTE开发目录 - 设计文档 ===
    "../hte-dev/docs/orchestrator_design.md"
    "../hte-dev/docs/sqlite_state_design.md"
    "../hte-dev/docs/verifier_replay_design.md"

    # === HTE开发目录 - 原型代码 ===
    "../hte-dev/prototypes/write_state_sqlite.py"
    "../hte-dev/prototypes/test_orchestrator.py"
    "../hte-dev/prototypes/test_write_state_sqlite.py"

    # === HTE开发目录 - 进度和证据 ===
    "../hte-dev/.phase_control/PROGRESS.md"
    "../hte-dev/.phase_control/phases.json"
)

# ============================================================
#  tar.gz 模式（默认）
# ============================================================
if [ "$MODE" = "tar" ]; then
    TAR_OUTPUT="${OUTPUT_FILE:-${PROJECT_ROOT}/hmte-pack-$(date +%Y%m%d-%H%M%S).tar.gz}"

    echo "📦 开始 tar.gz 打包..."
    echo "项目根目录: $PROJECT_ROOT"
    echo "输出文件: $TAR_OUTPUT"
    echo ""

    # 创建临时目录
    _tmpdir=$(mktemp -d)
    PACK_DIR="$_tmpdir/hmte-pack"
    mkdir -p "$PACK_DIR"

    packed=0
    skipped=0
    for file in "${FILES[@]}"; do
        src="$PROJECT_ROOT/$file"
        if [ -f "$src" ]; then
            dest_dir="$PACK_DIR/$(dirname "$file")"
            mkdir -p "$dest_dir"
            cp "$src" "$PACK_DIR/$file"
            echo "✓ 打包: $file"
            ((packed++)) || true
        else
            echo "⚠️  跳过: $file"
            ((skipped++)) || true
        fi
    done

    # 打包
    cd "$_tmpdir"
    tar czf "$TAR_OUTPUT" hmte-pack/
    rm -rf "$_tmpdir"

    echo ""
    echo "✅ tar.gz 打包完成！"
    echo "📄 输出: $TAR_OUTPUT"
    echo "📊 大小: $(du -h "$TAR_OUTPUT" | cut -f1)"
    echo "📦 打包文件: $packed 个"
    echo "⚠️  跳过文件: $skipped 个"
    exit 0
fi

# ============================================================
#  Markdown 模式（旧模式，通过 --markdown 启用）
# ============================================================
OUTPUT_FILE="${OUTPUT_FILE:-${PROJECT_ROOT}/hmte-full-pack-$(date +%Y%m%d-%H%M%S).md}"

echo "📦 开始打包项目文件（Markdown模式）..."
echo "项目根目录: $PROJECT_ROOT"
echo "输出文件: $OUTPUT_FILE"
echo ""

# 创建输出文件
cat > "$OUTPUT_FILE" <<HEADER
# HTE (Hermes Team Engine) - 完整项目打包

> 自动生成时间: $(date '+%Y-%m-%d %H:%M:%S')
> 用途: 提供给AI进行全面分析、代码审计、优化建议

---

## 项目概述

HTE是一个为Hermes Agent设计的多Agent协作工作流系统，实现Leader/Worker/Verifier三角色协作、阶段门禁、证据束验证机制。

**核心机制**：
- Leader (master-planner): 拆解任务、制定阶段计划、控制推进
- Worker (phase-executor): 执行具体阶段、提交证据束
- Verifier: 独立审计、决定PASS/FAIL/BLOCK

**关键约束**：
- 未生成phases.json前不得编辑业务代码
- 未生成evidence bundle前不得请求verifier
- verifier未输出PASS不得进入下阶段
- Leader必须通过delegate_task启动Worker和Verifier子Agent

---

HEADER

# 打包每个文件
packed=0
skipped=0
for file in "${FILES[@]}"; do
    filepath="$PROJECT_ROOT/$file"

    if [ ! -f "$filepath" ]; then
        echo "⚠️  跳过不存在的文件: $file"
        ((skipped++)) || true
        continue
    fi

    echo "✓ 打包: $file"
    ((packed++)) || true

    # 确定文件扩展名
    case "$file" in
        *.md) ext="markdown" ;;
        *.py) ext="python" ;;
        *.sh) ext="bash" ;;
        *.json) ext="json" ;;
        *.yaml|*.yml) ext="yaml" ;;
        *) ext="text" ;;
    esac

    # 添加文件分隔符和标题
    cat >> "$OUTPUT_FILE" <<EOF

---

## 📄 \\\`$file\\\`

\`\`\`$ext
EOF

    # 添加文件内容
    cat "$filepath" >> "$OUTPUT_FILE"

    # 关闭代码块
    echo '```' >> "$OUTPUT_FILE"
done

# 添加目录结构
echo "" >> "$OUTPUT_FILE"
echo "---" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "## 📁 项目目录结构" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"
cd "$PROJECT_ROOT"
find . -type f -not -path '*/.git/*' -not -path '*/__pycache__/*' -not -path '*/node_modules/*' -not -name '*.pyc' | sort | head -100 >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"

# 添加统计信息
echo "" >> "$OUTPUT_FILE"
echo "---" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "## 📊 项目统计" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"
echo "打包文件数: $packed / $((${#FILES[@]}))" >> "$OUTPUT_FILE"
echo "跳过文件数: $skipped" >> "$OUTPUT_FILE"
total_lines=0
for file in "${FILES[@]}"; do
    filepath="$PROJECT_ROOT/$file"
    if [ -f "$filepath" ]; then
        lines=$(wc -l < "$filepath" | tr -d ' ')
        total_lines=$((total_lines + lines))
    fi
done
echo "总代码行数: $total_lines" >> "$OUTPUT_FILE"
echo "打包时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"

# 添加使用说明
cat >> "$OUTPUT_FILE" <<'FOOTER'

---

## 💡 如何使用这个打包文件

### 发给AI分析时的提示词模板

```
这是一个Hermes Agent的多Agent协作工作流项目（HTE）。请全面分析：

1. 架构设计是否合理（角色分工、状态机、证据流）
2. 代码质量问题（安全、性能、可维护性）
3. 与Hermes Agent的适配性（是否充分利用Hermes特性）
4. 优化建议（短期、中期、长期）

重点关注：
- Orchestrator编排器的完整性和错误处理
- SQLite状态管理的schema设计
- 证据束的完整性和可追溯性
- 阶段门禁的强制性
- Verifier复现验证机制的可行性
- delegate_task强制使用的合理性
```

### 快速定位关键文件

- **理解架构**: 先读 `HERMES.md` 和 `README.md`
- **理解角色**: 读 `src/agents/*.md`
- **理解流程**: 读 `src/skills/hmte/SKILL.md`
- **理解Orchestrator**: 读 `src/skills/hmte/scripts/orchestrator.py`
- **理解SQLite设计**: 读 `hte-dev/docs/sqlite_state_design.md`
- **理解Verifier复现**: 读 `hte-dev/docs/verifier_replay_design.md`
- **查看进度**: 读 `hte-dev/.phase_control/PROGRESS.md`

FOOTER

echo ""
echo "✅ 打包完成！"
echo "📄 输出文件: $OUTPUT_FILE"
echo "📊 文件大小: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "📦 打包文件: $packed 个"
echo ""
echo "现在可以将这个文件发给任何AI进行分析。"
