# HTE 独立审计报告

**审计日期**: 2026-05-27  
**审计模型**: mimo-v2.5-pro (independent, from-scratch audit)  
**审计范围**: F:/AI/mavis-team-engine 全部文件  
**审计视角**: 用户视角 — 一个从未接触过该项目的新用户

---

## 执行摘要

| 维度 | 评级 | 问题数 |
|------|------|--------|
| 1. 用户体验 | ⚠️ 中等 | 5 |
| 2. 技术准确性 | 🔴 需修复 | 5 |
| 3. 品牌一致性 | ⚠️ 中等 | 2 |
| 4. 安全性 | ✅ 良好 | 1 |
| 5. 完整性 | ⚠️ 中等 | 3 |

**总体评级**: ⚠️ **可用但需修补** — 不阻塞本地使用，但多处 Hermes 平台适配问题会导致实际行为与文档描述不符。

---

## 1. 用户体验（README 可读性、安装说明）

### 正面

- README 结构清晰：What → Architecture → Quick Start → Usage → Structure → Security → Config，层次递进
- ASCII 架构图直观有效
- 三个角色表格对比一目了然
- Evidence Bundle 和 Verdict 格式有完整示例
- Troubleshooting 部分实用
- Roadmap 和 Comparison 表格增加了专业感

### 问题

#### 🟡 ISSUE-UX-1: Quick Start 第 3 步的 cp -r 使用占位符路径

```
cp -r /path/to/mavis-team-engine/.phase_control .
```

紧跟在 `git clone` 之后，用户不知道 clone 到了哪里、该用什么路径。应改为：

```bash
# 假设你在某个项目目录下，mavis-team-engine 已 clone 到同级
cp -r ../mavis-team-engine/.phase_control .
cp -r ../mavis-team-engine/scripts .
```

或给出明确说明。

**严重程度**: 低

#### 🟡 ISSUE-UX-2: Manual Testing 步骤编号错误

README 第 549-557 行 Manual Testing 部分：
```
3. Start session
2. Create test phase  ← 编号倒退
3. Invoke skill
4. Check status
```

应该是 1-7 连续编号，当前从 3 开始且有重复。

**严重程度**: 低（仅排版）

#### 🟡 ISSUE-UX-3: Windows 兼容性未提前说明

README Prerequisites 只写了 "Python 3.8+"、"Bash (Unix-like shell)"，但：
- `write_state.py` 使用 `fcntl`（Unix-only）
- `grep -oP`（Perl regex）在 MSYS/Git Bash 不可用
- `pretool_guard.sh` 的 `grep -qE` 在某些 Windows shell 有差异

README Roadmap 第 718 行提到 "Windows compatibility improvements"，说明作者知道这是问题，但当前没有警告用户。

**严重程度**: 中

#### 🟡 ISSUE-UX-4: Troubleshooting 中 write_state.py 路径对 Hermes 用户不友好

README 第 635 行：
```bash
python3 ~/.hermes/profiles/default/skills/hmte/scripts/write_state.py \
  .phase_control/state.json phase_status=passed
```

用户需要手动拼接 profile 路径，且 `python3` 在 Windows 上可能不可用。应提供更简单的命令或封装脚本。

**严重程度**: 低

#### 🟡 ISSUE-UX-5: 项目统计数据自相矛盾

- README 第 737 行: "~5,700+ (1,148 scripts + 4,524 docs)"，"39 files"
- FINAL_REPORT.md 第 18 行: "~4,000 lines"，"25 files"
- FINAL_REPORT.md 第 290 行: "~4,500+"，"26 files"
- VERIFICATION_REPORT.md 第 21 行: "24 files"

四处数据不一致。新用户看到会怀疑文档质量。

**严重程度**: 中（信任度问题）

---

## 2. 技术准确性（Hermes 架构描述）

### 正面

- PLATFORM_HISTORY.md 准确描述了 Claude Code vs Hermes 的架构差异
- "project-local .phase_control/ vs global skill" 区分正确
- `.claude/` 保留理由（历史参考 + 向后兼容）解释清晰

### 问题

#### 🔴 ISSUE-TECH-1: Agent 定义使用 Claude Code 语法，与 Hermes delegate_task 不匹配

`master-planner.md` 第 87-101 行描述的子代理调用方式：

```
使用 Agent 工具：
- subagent_type: "phase-executor"
- prompt: "请执行以下阶段..."
```

这是 Claude Code 的 `Agent` 工具语法。Hermes 使用 `delegate_task`，参数为 `goal` + `context` + `toolsets`，没有 `subagent_type`。在 Hermes 中，这些 agent 定义文件不会自动产生 "call phase-executor subagent" 的行为 — Hermes 的 delegate_task 是通用的子代理派发，不按 agent 文件名路由。

**影响**: 用户在 Hermes 中使用时，Leader 不会按预期调用 phase-executor/verifier 作为独立子代理，而是在同一个会话中按 skill 指令执行。

**严重程度**: 高（核心架构行为与文档描述不符）

#### 🔴 ISSUE-TECH-2: Hooks 在 Hermes 中不会自动执行

`pretool_guard.sh`、`stop_gate.sh`、`task_naming.sh` 位于 `.claude/hooks/`，这是 Claude Code 的 hooks 目录约定。PLATFORM_HISTORY.md 第 186 行提到：

> Hermes: Hooks must be registered in skill manifest

但 SKILL.md 中没有注册任何 hooks。这意味着：
- `pretool_guard.sh` 的危险命令阻断 **不生效**
- `stop_gate.sh` 的停止门控 **不生效**
- 安全防护机制在 Hermes 平台上 **完全不起作用**

**严重程度**: 高（安全功能失效，用户不知道）

#### 🟡 ISSUE-TECH-3: `isolation: worktree` 在 Hermes 中无对应实现

`phase-executor.md` 声明 `isolation: worktree`，Hermes 的 delegate_task 没有 worktree 隔离功能。Worker 实际在主目录执行，不会创建隔离的 git worktree。

**严重程度**: 中（声称的隔离不存在）

#### 🟡 ISSUE-TECH-4: Agent frontmatter 中的模型名使用 Claude Code 术语

```yaml
model: opus      # Claude Code 术语
model: sonnet    # Claude Code 术语
```

Hermes 中应使用 provider + model 格式（如 `anthropic/claude-opus-4-7`）。当前写法可能被 Hermes 解析为默认模型，而非预期的 Opus/Sonnet。

**严重程度**: 中（模型选择可能不符合预期）

#### 🟡 ISSUE-TECH-5: SKILL.md 的 allowed-tools 是 Claude Code 格式

```yaml
allowed-tools: Read Grep Glob Bash Edit Write Agent
```

Hermes skill 系统的 allowed-tools 格式不同。这些权限声明在 Hermes 中可能被忽略。

**严重程度**: 低（不影响运行，但不产生预期的权限控制）

---

## 3. 品牌一致性（HMTE 使用）

### 正面

- README 标题一致使用 "HMTE (Hermes Mavis Team Engine)"
- LICENSE 使用 "HMTE Contributors"
- install-to-hermes.sh 正确使用 `SKILL_NAME="hmte"`
- Disclaimer 部分清晰且专业
- Acknowledgments 部分存在且内容正确

### 问题

#### 🟡 ISSUE-BRAND-1: Skill 名称 "mavis-team-engine" vs "hmte" 不一致

SKILL.md frontmatter: `name: mavis-team-engine`  
install-to-hermes.sh: 安装到 `skills/hmte/`  
文档中多处说 "invoke the 'mavis-team-engine' skill"

实际上安装后的 skill 目录名是 `hmte`，但 SKILL.md 内部声明的 name 是 `mavis-team-engine`。Hermes skill 发现机制以目录名为准，所以 skill 名称实际是 `hmte`。但文档中多处说 "invoke the 'mavis-team-engine' skill"，用户按文档操作会找不到。

**影响**: 用户按 README 指示说 "Please use the mavis-team-engine skill"，但 Hermes 只认识 `hmte`。

**严重程度**: 中（直接影响使用）

#### 🟡 ISSUE-BRAND-2: 大量元数据文件名不一致

项目包含多种命名风格的文档：
- `FINAL_REPORT.md` — 全大写
- `IMPLEMENTATION_PLAN.md` — 全大写
- `PLATFORM_HISTORY.md` — 全大写
- `HERMES.md` — 全大写
- `SECURITY_FIXES.md` — 全大写
- `LEGAL_REVIEW.md` — 全大写

全部大写的文件名在 git 仓库中不常见，且与其他文件（`install-to-hermes.sh`、`README.md`、`LICENSE`）风格不统一。这不是功能性问题，但影响专业感。

**严重程度**: 低（仅美观）

---

## 4. 安全性（无敏感信息）

### 正面

- 全文件扫描未发现 API keys、tokens、密码、邮箱、电话、真实姓名
- GitHub 用户名仅出现在 git remote URL，不在代码中
- `.gitignore` 正确排除运行时状态文件（state.json、run.lock、evidence/*.json 等）
- LICENSE 使用通用 copyright holder "HMTE Contributors"
- 无第三方依赖，无 GPL 污染风险

### 安全功能评估

| 功能 | 实现状态 | Hermes 生效？ |
|------|----------|--------------|
| 文件锁（fcntl） | ✅ 已实现 | ✅ 生效（Python 脚本） |
| 路径遍历防护 | ✅ 已实现 | ✅ 生效（Bash 脚本） |
| JSON 注入防护 | ✅ 已实现 | ✅ 生效（Python json.dump） |
| 原子锁创建 | ✅ 已实现 | ✅ 生效（bash noclobber） |
| 危险命令阻断 | ✅ 已实现 | ❌ **不生效**（hooks 不注册） |
| 停止门控 | ✅ 已实现 | ❌ **不生效**（hooks 不注册） |
| 任务命名约束 | ✅ 已实现 | ❌ **不生效**（hooks 不注册） |

### 问题

#### 🔴 ISSUE-SEC-1: 安全 hooks 在 Hermes 平台上不生效（同 ISSUE-TECH-2）

这是技术准确性问题，但从安全维度看影响更大：README 第 449-477 行声称的安全特性（dangerous command blocking、stop gate）在 Hermes 上实际上 **不工作**。用户以为有安全防护，实际上没有。

**严重程度**: 高

#### 🟡 ISSUE-SEC-2: collect_evidence.sh 中 Python heredoc 重复执行

`collect_evidence.sh` 第 39-92 行和第 98-151 行包含完全相同的 Python 代码块。第一个 heredoc 在 `export` 之前执行，环境变量为空，创建的 evidence 文件内容为空值。第二个 heredoc 在 `export` 之后执行，覆盖第一个的结果。

功能上不影响最终结果（第二次覆盖第一次），但这是一个明显的复制粘贴错误。

**严重程度**: 低（功能不受影响）

---

## 5. 完整性（文件引用、链接有效性）

### 正面

- 目录结构描述与实际文件一致
- Documentation 部分列出的 9 个文档全部存在
- 内部链接（PLATFORM_HISTORY.md、LICENSE 等）格式正确
- `.phase_control/` 目录结构与文档描述匹配

### 问题

#### 🔴 ISSUE-COMP-1: GitHub 仓库 URL 无法验证

README 中所有 GitHub 链接指向：
```
https://github.com/YOUR_USERNAME/mavis-team-engine
```

包括 clone URL、Issues、Discussions、Wiki。如果仓库不存在或为 private，用户按 README 操作第一步就失败。

**严重程度**: 高（阻塞安装）

#### 🟡 ISSUE-COMP-2: FINAL_REPORT.md 引用不存在的文件名

FINAL_REPORT.md 第 153 行：
```
2. `CLAUDE.md` - Project rules
```

实际文件名是 `HERMES.md`。这是迁移重命名后未更新的遗留。

**严重程度**: 低（仅文档不一致）

#### 🟡 ISSUE-COMP-3: 实际文件数量与文档声称不一致

实际扫描（不含 .git）：
```
.claude/agents/           3 files
.claude/hooks/            3 files
.claude/skills/.../       7 files
.claude/README.md         1 file
.phase_control/          ~30 files (含 evidence/verdicts)
scripts/                  4 files
根目录文档               13 files (README, LICENSE, HERMES.md, etc.)
─────────────────────────
总计约                   ~61 files
```

文档声称：24 files（VERIFICATION_REPORT）、25 files（FINAL_REPORT）、26 files（FINAL_REPORT 另一处）、39 files（README）。全部不准确。

**严重程度**: 低

---

## 汇总：按严重程度排序

### 🔴 高严重度（应修复后开源）

| ID | 问题 | 影响 |
|----|------|------|
| TECH-1 | Agent 调用语法是 Claude Code 格式，Hermes 不匹配 | Leader 无法按描述调度 Worker/Verifier |
| TECH-2 / SEC-1 | Hooks 在 Hermes 不注册，安全功能不生效 | 用户以为有防护，实际没有 |
| COMP-1 | GitHub URL 可能不存在 | 安装第一步就失败 |

### 🟡 中严重度（建议修复）

| ID | 问题 |
|----|------|
| UX-3 | Windows 兼容性未提前说明 |
| UX-5 | 项目统计数据四处不一致 |
| TECH-3 | worktree 隔离在 Hermes 不存在 |
| TECH-4 | 模型名用 Claude Code 术语 |
| BRAND-1 | skill 名 "mavis-team-engine" vs "hmte" 不一致 |

### 🟢 低严重度（可忽略）

| ID | 问题 |
|----|------|
| UX-1 | cp -r 占位符路径 |
| UX-2 | Manual Testing 编号错误 |
| UX-4 | write_state.py 路径不友好 |
| TECH-5 | allowed-tools 格式 |
| BRAND-2 | 文件名大小写风格不统一 |
| SEC-2 | collect_evidence.sh heredoc 重复 |
| COMP-2 | FINAL_REPORT 引用 CLAUDE.md |
| COMP-3 | 文件计数不准确 |

---

## 根因分析

项目的核心问题在于：**迁移是从 Claude Code 到 Hermes 的，但只完成了文件/文档层面的迁移，没有完成架构层面的适配。**

具体表现为：
1. Agent 定义仍按 Claude Code 的 Agent/subagent_type 语法编写
2. Hooks 没有注册到 Hermes 的 skill manifest
3. 文档中 "Claude Code" 被替换成了 "Hermes"，但实际运行机制还是 Claude Code 的
4. SKILL.md 的 frontmatter 字段沿用 Claude Code 格式

**本质**: 这是一个 Claude Code 原生项目，通过文档重写包装成了 Hermes 项目，但 Hermes 平台的原生集成（delegate_task、skill hooks、model provider 语法）尚未实现。

---

## 修复建议优先级

1. **P0（开源前必须）**: 确认 GitHub 仓库可访问，或移除 clone URL
2. **P0**: 在 README 显著位置标注 "当前 Hermes 集成处于 beta 状态，部分功能（hooks、agent routing）需要手动配置"
3. **P1**: 更新 agent 定义中的调用示例为 Hermes delegate_task 语法
4. **P1**: 将 hooks 逻辑迁移到 Hermes skill manifest 或在 SKILL.md 中说明手动注册步骤
5. **P1**: 统一 skill 名称为 `hmte`，更新所有文档引用
6. **P2**: 修复统计数字不一致
7. **P2**: 修复 Manual Testing 编号
8. **P2**: 添加 Windows 兼容性说明

---

**审计完成时间**: 2026-05-27  
**审计方法**: 全文件逐一阅读 + 交叉引用验证 + Hermes 架构知识比对
