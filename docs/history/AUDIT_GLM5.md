# HTE 全面审计报告

**审计日期**: 2026-05-27
**审计员**: GLM-5.1 (独立审计，与此前 Kiro/DeepSeek V4 Pro 审计无关)
**项目**: F:/AI/mavis-team-engine
**版本**: 当前 master 分支（commit 1ac974a）
**审计范围**: 全部 33 个非 .git 文件

---

## 一、执行摘要

**总体评级**: ⚠️ **可开源，但需修复若干问题**

项目已基本完成 Claude Code → Hermes 迁移，但存在以下类别的问题：
- **严重 (CRITICAL)**: 2 项 — write_state.py 在 Windows 上直接崩溃；collect_evidence.sh 有重复执行的 Python 代码块
- **高 (HIGH)**: 5 项 — 法律文件未覆盖 "Mavis" 商标风险；README 含大量虚假示例和功能声称
- **中 (MEDIUM)**: 8 项 — `.claude/` 目录残留未清理干净；多处硬编码路径；文档碎片化严重
- **低 (LOW)**: 若干 — 代码风格不一致、文档冗余等

---

## 二、迁移完整性（Claude Code 残留）

### 2.1 [CRITICAL] `.claude/` 整个目录仍然存在

**现状**: `.claude/` 目录包含完整的 Claude Code 原始结构（agents/、hooks/、skills/），共 12 个文件。

**问题**:
- 这不是一个"遗留参考"问题——install-to-hermes.sh 脚本的 `SOURCE_DIR` 直接指向 `.claude/skills/mavis-team-engine/`：
  ```
  SOURCE_DIR=".claude/skills/mavis-team-engine/"
  ```
  即 Hermes 安装流程**依赖** Claude Code 目录结构。这意味着如果你删除 `.claude/`，安装脚本就会失败。

- `.claude/README.md` 自称"Legacy Structure / DEPRECATED"，但实际是核心功能路径。

**根因**: 迁移只做了一半——把 Hermes 版本安装到 `~/.hermes/profiles/default/skills/hmte/`，但没有让 `install-to-hermes.sh` 从独立的源目录（如 `src/`）复制文件。`.claude/` 仍是唯一的文件来源。

**影响**: 开源后用户看到项目一半是 "Hermes-native" 一半是 Claude Code 结构，造成困惑。更重要的是，`install-to-hermes.sh` 里的 `SOURCE_DIR` 指向 `.claude/`，如果用户只用 Hermes 不用 Claude Code，这个路径没有语义意义。

**建议**: 创建 `src/` 目录作为唯一的技能源，让 `install-to-hermes.sh` 从 `src/` 读取。`.claude/` 可以作为可选的兼容层保留，但不应是安装脚本的依赖。

### 2.2 [MEDIUM] Agent 定义文件仍为 Claude Code 格式

**位置**: `.claude/agents/master-planner.md`、`phase-executor.md`、`verifier.md`

**问题**: 这些文件的 YAML frontmatter 使用 Claude Code 专属字段：
```yaml
tools: Read Grep Glob Bash Edit Write Agent
permissionMode: plan
maxTurns: 20
color: purple
```

这些字段（`tools`、`permissionMode`、`maxTurns`、`color`）是 Claude Code agent 协议的一部分，在 Hermes 中不生效。Hermes 的 skill 系统有自己的 frontmatter 格式（`allowed-tools` 等字段在 SKILL.md 中使用）。

**影响**: Claude Code 用户可以直接使用；Hermes 用户看到这些定义但 Hermes 并不消费它们（Hermes 版本的 agents 安装在 `~/.hermes/profiles/default/skills/hmte/agents/` 但实际执行时由 Hermes 的 delegate_task 机制驱动）。

**建议**: 在文件头部或 PLATFORM_HISTORY.md 中明确说明：这些 frontmatter 字段仅 Claude Code 使用，Hermes 用户参考 SKILL.md。

### 2.3 [LOW] 文档中 Claude Code 引用过于频繁

统计：在全部 .md 文件中搜索 "Claude Code" 或 ".claude" 相关引用，超过 50 处。对于自称 "Hermes-native" 的项目，这个密度过高。

README.md 中有专门的 "For Claude Code Users (Legacy)" 章节（行 160-184），这是合理的向后兼容说明。但其他文档如 VERIFICATION_REPORT.md、FINAL_REPORT.md、IMPLEMENTATION_SUMMARY.md 大量引用 `.claude/` 路径，这些是在 Hermes 迁移前的旧报告，没有更新。

---

## 三、文档准确性

### 3.1 [HIGH] README.md 包含大量虚构的功能演示

**位置**: README.md 行 242-374

**问题**: "Example: Implementing User Authentication" 章节描述了一个完整的 JWT 认证实现流程，包括：
- "Worker creates design document"
- "Worker implements login API in isolated worktree"
- "Changed files: src/api/auth.js"
- "Test results: 5 passed, 0 failed"
- "Coverage now 85%"
- "JWT token generation works"
- "bcrypt used for passwords"

**这是虚构的**。项目中没有任何实际的认证代码、测试框架、或 JWT 实现。这是一个"如果用户请求做认证，系统会怎么做"的假设性描述，但写成了已完成的事实陈述。

**同样的问题**: 行 290-374 的 Evidence Bundle 和 Verdict Format 示例使用了 `src/api/auth.js`、`tests/auth.test.js` 等不存在的文件路径。

**影响**: 用户可能误以为 HMTE 自带认证库或测试框架。

**建议**: 将示例章节的标题改为 "Example: What Happens When You Request..."，明确标注这是流程演示而非已实现功能。使用通用文件名而非具体的 `auth.js`。

### 3.2 [HIGH] README.md 行 577-579 的性能数据无依据

**位置**: README.md 行 577-579
```
- Simple phase (add function): 2-5 minutes
- Medium phase (implement API): 5-15 minutes
- Complex phase (full feature): 15-30 minutes
```

**问题**: 没有任何 benchmark 或测试数据支撑这些数字。项目也没有自动化计时功能（`.phase_control/traces/` 目录在 .gitignore 中，但从未被代码实际使用）。

### 3.3 [HIGH] README.md 行 563 "7x token" 数据无依据

**位置**: README.md 行 563
```
Multi-agent workflows consume approximately **7x** normal conversation tokens
```

**问题**: "7x" 这个数字没有测量依据。Leader ~2x + Worker ~3x + Verifier ~2x 的分解是主观估计，不是实测数据。README 没有注明"估算值"。

### 3.4 [MEDIUM] README.md 行 737-740 项目统计数据可疑

```
- **Lines of Code**: ~5,700+ (1,148 scripts + 4,524 docs)
- **Files**: 39 (scripts, docs, configs)
```

**问题**: 实际文件数（非 .git）为 33 个，不是 39。"5,700+ lines" 包含大量空行和模板内容。脚本行数 1,148 行中，collect_evidence.sh 重复了一个完整的 Python 代码块（约 50 行重复）。

### 3.5 [MEDIUM] AUDIT_REPORT.md 和 VERIFICATION_REPORT.md 过时

这两个文件是迁移过程中 Kiro (DeepSeek V4 Pro) 产生的审计和验证报告，描述的是迁移过程中的状态。现在项目已迁完，这些文件的结论可能已不适用于当前版本。

特别是 AUDIT_REPORT.md 行 4 标注 "审计员: Kiro (DeepSeek V4 Pro)"，这份审计报告的发现可能在后续修复中已解决，但文件没有更新。

### 3.6 [MEDIUM] 文档碎片化严重

项目有 12 个顶层 .md 文件（不含 .claude/ 下面的）：

| 文件 | 内容 | 是否必要 |
|------|------|---------|
| README.md | 主文档 | ✅ |
| LICENSE | 许可证 | ✅ |
| HERMES.md | Hermes 规则 | ✅ |
| PLATFORM_HISTORY.md | 迁移历史 | ✅ |
| IMPLEMENTATION_PLAN.md | 原始设计 | ⚠️ 开发完成后价值降低 |
| IMPLEMENTATION_SUMMARY.md | 构建总结 | ⚠️ 与 FINAL_REPORT 重复 |
| FINAL_REPORT.md | 完成报告 | ⚠️ 过时 |
| VERIFICATION_REPORT.md | 验证报告 | ⚠️ 过时 |
| SECURITY_FIXES.md | 安全修复 | ⚠️ 已合并到 README |
| AUDIT_REPORT.md | 旧审计 | ⚠️ 被本报告取代 |
| MIGRATION_COMPLETE.md | 迁移完成报告 | ⚠️ 历史文件 |
| GITHUB_UPLOAD_CHECKLIST.md | 上传清单 | ⚠️ 一次性 |
| GITHUB_RENAME.md | 重命名指南 | ⚠️ 一次性 |
| PUSH_INSTRUCTIONS.md | 推送指南 | ⚠️ 一次性 |

8 个文件是迁移过程的产物，开源后对新用户价值很低。建议整合为一个 `docs/` 目录或 `HISTORY.md`。

---

## 四、法律合规

### 4.1 [HIGH] "Mavis" 名称的商标风险未充分说明

**现状**: README.md 行 8-16 有 Disclaimer 章节，LEGAL_REVIEW.md 行 60-74 有 "第三方品牌使用" 段落。两者都声称"无风险"。

**问题**: 
- "Mavis" 是 MiniMax 的产品名称（不是论文中的概念）。HMTE 的全称 "Hermes Mavis Team Engine" 直接将 "Mavis" 作为品牌名称的一部分。
- LEGAL_REVIEW.md 行 63-64 说："使用了明确的 Disclaimer 说明关系"——但 MIT 许可证下，Disclaimer 不等于商标授权。MiniMax 可以主张商标侵权。
- 项目仓库名 `mavis-team-engine` 也包含 "Mavis"。
- LEGAL_REVIEW.md 行 64 说 "仅在描述性语境中引用，未作为商标使用"——但实际上 "Mavis" 被用作项目名的一部分，这不是"描述性使用"，是"商标性使用"。

**建议**: 
1. 将项目名从 "Hermes Mavis Team Engine" 改为不含 "Mavis" 的名称（如 "Hermes Team Engine" / HTE）
2. 在 README 中将 "Mavis" 标注为 MiniMax 的商标，仅在致谢和灵感说明中使用
3. 或至少咨询律师确认 MiniMax 的商标政策

### 4.2 [MEDIUM] 第三方 GitHub 用户名硬编码

**位置**: 多处
```
git clone https://github.com/YOUR_USERNAME/mavis-team-engine.git
```

出现于 README.md 行 128、681，IMPLEMENTATION_SUMMARY.md 行 140，MIGRATION_COMPLETE.md 行 187 等。

**问题**: 这是某个具体用户的 GitHub 账号名。如果项目要开源到组织账号或其他用户下，所有这些引用都需要更新。

**建议**: 使用 `YOUR_USERNAME` 或 GitHub 组织名占位符。

### 4.3 [LOW] MIT License 的 Copyright 行使用通用名称

**位置**: LICENSE 行 3
```
Copyright (c) 2026 HMTE Contributors
```

这是合理的做法，但如果项目有主要维护者，通常会在 NOTICE 文件中列出。

---

## 五、代码质量

### 5.1 [CRITICAL] write_state.py 使用 fcntl，Windows 不兼容

**位置**: `.claude/skills/mavis-team-engine/scripts/write_state.py` 行 7

```python
import fcntl
```

`fcntl` 是 Unix 专属模块，在 Windows 上运行会直接 `ImportError`。README.md 行 718 Roadmap 中提到了 "Windows compatibility improvements" 但标记为 v1.1 计划。

**问题**: `mavis-start.sh` 和 `mavis-status.sh` 都依赖 `write_state.py`。整个 HMTE 工作流在 Windows 上不可用。README 行 119 的 Prerequisites 只说 "Bash (Unix-like shell)"，没有明确说明不支持 Windows。

**建议**: 
1. 使用 `msvcrt` (Windows) / `fcntl` (Unix) 条件导入
2. 或使用跨平台库如 `filelock`（pip install filelock）
3. 至少在 README Prerequisites 中明确标注 "Unix/macOS only, Windows not supported"

### 5.2 [CRITICAL] collect_evidence.sh 有重复的 Python 代码块

**位置**: `.claude/skills/mavis-team-engine/scripts/collect_evidence.sh`

脚本中有两个完全相同的 Python heredoc 块（行 42-99 和行 106-152），都执行相同的 JSON 生成逻辑。

**根因**: 可能是编辑时的 copy-paste 错误。第一个 Python 块在行 42 定义了 `evidence` 字典并写入文件，然后行 105 的 `export` 导出环境变量，然后行 108 开始的第二个 Python 块做了完全一样的事情。

**问题**: 
1. 每次执行会写两次文件（第二次覆盖第一次，所以功能上不影响结果）
2. 代码维护成本翻倍
3. 环境变量 export 在第一个 Python 块之后才执行，所以第一个块实际上无法获取环境变量——这说明第一个块是死代码，但因为它从 `os.environ` 读取，而 export 在它之后，第一个块写入的 `phase_id` 等字段会是空字符串

**实际行为**: 第一个 Python 块生成空字段（PHASE_ID/ATTEMPT/TIMESTAMP/EVIDENCE_FILE 环境变量尚未 export），第二个块正确生成。但这意味着第一个文件写入是错误的，只是被第二个覆盖了。

**建议**: 删除第一个 Python 块（行 42-99 的 heredoc），保留 export + 第二个 Python 块。或将 export 移到两个块之前。

### 5.3 [MEDIUM] pretool_guard.sh 的安全检测可绕过

**位置**: `.claude/hooks/pretool_guard.sh`

**问题**:
1. 行 16: `grep -qE` 匹配 `rm -rf` 的正则只检查 `-r` 和 `-f` 的存在，不检查顺序。`rm -fr /` 会被部分匹配但不完全。实际测试：`rm -fr /etc` 应该被拦截，正则 `rm\s+.*-[a-z]*r[a-z]*f` 要求 r 在 f 前面，所以 `rm -fr` 不匹配第一个模式，但第二个模式 `rm\s+.*-[a-z]*f[a-z]*r` 匹配——OK，双模式可以覆盖。

2. 行 40: 特权升级检测 `chmod 04755` 不匹配，因为正则 `chmod\s+[0-9]*[4-7]` 只匹配包含 4-7 的模式。`chmod 000` 不会被拦截——这不是安全问题，但 `chmod 777` 会被拦截（包含 7），而 `chmod 666` 也会被拦截（包含 6）。这意味着普通的 `chmod 600 ~/.ssh/config` 也会被拦截。

3. 行 46: 网络检测 `curl.*\|` 会误拦 `curl https://example.com | jq .` 这种常见管道操作。

4. 整个脚本只在 `TOOL_NAME = "Bash"` 时生效，不覆盖 Edit/Write 工具。

**影响**: 安全钩子误报率高，可能阻碍正常操作；同时有些危险命令可以通过变体绕过。

**建议**: 针对误报问题，将某些 block 改为 warn。或使用更精确的白名单。

### 5.4 [MEDIUM] install-to-hermes.sh 不检查目标目录是否已存在

**位置**: install-to-hermes.sh

**问题**: 如果 `~/.hermes/profiles/default/skills/hmte/` 已存在旧版本安装，脚本直接 `cp -r` 覆盖，没有：
1. 备份旧版本
2. 提示用户确认覆盖
3. 检查版本差异

**建议**: 添加 `--force` 参数或交互确认。

### 5.5 [MEDIUM] scripts/ 使用 "mavis-" 前缀

**位置**: `scripts/mavis-start.sh`、`mavis-stop.sh`、`mavis-status.sh`、`mavis-e2e.sh`

**问题**: 项目已改名为 HMTE，但脚本仍使用 `mavis-` 前缀。这与品牌迁移不一致。README 和文档也大量引用 `mavis-start.sh` 等名称。

**建议**: 提供 `hmte-start.sh` 等新名称，保留 `mavis-*` 作为软链接/别名。

### 5.6 [LOW] Python 代码使用 `python3` 命令

**位置**: collect_evidence.sh 中 `python3 << 'PYTHON_EOF'`

**问题**: 在 Windows/MSYS2 环境中 `python3` 可能指向 Windows Store Python（版本不对）或不存在。项目应该使用 `python` 或在脚本开头检测可用的 Python 命令。

### 5.7 [LOW] e2e 测试的依赖不明确

**位置**: scripts/mavis-e2e.sh

e2e 测试依赖 `jq`，如果不可用则跳过关键验证步骤（行 83: `echo "⚠ jq not found, skipping JSON validation"`）。这意味着在没有 jq 的系统上，e2e 测试可能通过但实际没有验证 JSON 有效性。

---

## 六、开源准备度

### 6.1 [MEDIUM] GITHUB_UPLOAD_CHECKLIST.md 包含本地绝对路径

**位置**: GITHUB_UPLOAD_CHECKLIST.md 行 206
```
**Project Location**: `F:\AI\mavis-team-engine`
```

这是 Windows 本地路径，开源后需要移除。

### 6.2 [MEDIUM] .phase_control/verdicts/ 中有历史 verdict 文件

**位置**: `.phase_control/verdicts/` 目录包含迁移过程中的实际 verdict 文件：
- `phase_platform_migration_attempt_1.txt` (113 行)
- `phase_platform_migration_attempt_2.txt` (104 行)
- `phase_rename_project_attempt_1.txt` (79 行)
- `phase_update_readme_attempt_1.txt` (18 行)
- `phase_verification_attempt_1.txt` (160 行)

虽然 `.gitignore` 中有 `.phase_control/verdicts/*.txt`，但这些文件已经在 git 历史中（因为它们是在添加 .gitignore 规则之前被 commit 的）。需要 `git rm --cached` 清理。

### 6.3 [MEDIUM] 缺少 CONTRIBUTING.md 和 CODE_OF_CONDUCT.md

README 行 667-674 有简单的 Contributing 章节，但没有独立的 CONTRIBUTING.md。对于开源项目，通常需要：
- 独立的 CONTRIBUTING.md
- CODE_OF_CONDUCT.md（GitHub 推荐）
- Issue/PR 模板

### 6.4 [LOW] README 使用 GitHub badges 指向不存在的资源

**位置**: README.md 行 6
```
[![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-green.svg)]()
```

badge 的链接是 `()`（空链接），点击无响应。行 711-713 的 Support 链接指向 `YOUR_USERNAME/mavis-team-engine` 的 Issues/Discussions/Wiki——如果仓库还未创建，这些都是死链接。

### 6.5 [LOW] 缺少 CHANGELOG.md

项目经历了多个版本（原始开发 → 安全修复 → Hermes 迁移），但没有 CHANGELOG 记录。

---

## 七、问题汇总

| # | 严重度 | 类别 | 问题 | 修复建议 |
|---|--------|------|------|---------|
| 1 | CRITICAL | 代码 | write_state.py 使用 fcntl，Windows 不兼容 | 条件导入或使用 filelock 库 |
| 2 | CRITICAL | 代码 | collect_evidence.sh 重复 Python 块，第一个写入空数据 | 删除重复块或调整 export 顺序 |
| 3 | HIGH | 法律 | "Mavis" 商标风险未充分说明 | 改名或获取授权 |
| 4 | HIGH | 文档 | README 功能演示写成已完成事实 | 标注为流程演示 |
| 5 | HIGH | 文档 | 性能/token 数据无依据 | 标注为估算值或移除 |
| 6 | HIGH | 文档 | README 统计数据不准确 | 重新统计 |
| 7 | HIGH | 文档 | LEGAL_REVIEW 对商标风险判定过于乐观 | 补充律师意见或保守评估 |
| 8 | MEDIUM | 迁移 | `.claude/` 仍是 install-to-hermes.sh 的源目录 | 创建独立 src/ 目录 |
| 9 | MEDIUM | 迁移 | Agent frontmatter 使用 Claude Code 专属格式 | 添加说明或分离 Hermes 版本 |
| 10 | MEDIUM | 文档 | 8 个顶层 .md 是迁移产物，价值低 | 整合到 docs/ 或 HISTORY.md |
| 11 | MEDIUM | 文档 | AUDIT_REPORT / VERIFICATION_REPORT 过时 | 归档或更新 |
| 12 | MEDIUM | 法律 | 硬编码 GitHub 用户名 | 使用占位符 |
| 13 | MEDIUM | 代码 | pretool_guard.sh 误报率高 | 优化正则或改为 warn |
| 14 | MEDIUM | 代码 | install-to-hermes.sh 无覆盖确认 | 添加交互确认 |
| 15 | MEDIUM | 代码 | 脚本仍用 mavis- 前缀 | 改为 hmte- 或添加别名 |
| 16 | MEDIUM | 开源 | verdict 历史文件在 git 中 | git rm --cached |
| 17 | MEDIUM | 开源 | 缺 CONTRIBUTING.md / CODE_OF_CONDUCT.md | 添加 |
| 18 | MEDIUM | 开源 | GITHUB_UPLOAD_CHECKLIST.md 含本地路径 | 移除 |
| 19 | LOW | 迁移 | 文档中 Claude Code 引用超 50 处 | 逐步清理 |
| 20 | LOW | 代码 | python3 在 Windows 可能不可用 | 使用 python 或检测 |
| 21 | LOW | 代码 | e2e 测试在无 jq 时跳过验证 | 添加纯 Python JSON 验证 |
| 22 | LOW | 开源 | README badge 链接为空 | 更新或移除 |
| 23 | LOW | 开源 | 缺 CHANGELOG.md | 添加 |
| 24 | LOW | 开源 | 缺少独立 LICENSE 版权行 | 可选 |

---

## 八、与前次审计 (Kiro/DeepSeek V4 Pro) 的交叉验证

前次审计（AUDIT_REPORT.md）的主要发现：
1. ✅ "迁移基本完成" — 本次确认：功能上确实完成，但 `.claude/` 仍是源目录
2. ✅ "文档统计数据不准确" — 本次确认并扩展：不只是统计数字，还有虚构功能示例
3. ✅ "法律合规措施到位" — 本次部分不同意：MIT License ✅，但 "Mavis" 商标风险评估不足
4. ✅ "无敏感信息泄露" — 本次确认：确实无 API key/token 泄露
5. ✅ "部分文档存在占位符" — 本次确认并扩展：不只是占位符，有虚假示例

**本次新增发现（前次审计遗漏）**:
- write_state.py 的 fcntl/Windows 不兼容问题
- collect_evidence.sh 的重复代码块
- README 功能演示的虚构性问题
- "Mavis" 商标风险的更深入分析
- 8 个迁移产物文档的碎片化问题

---

## 九、修复优先级建议

### P0 — 必须在开源前修复
1. 修复 write_state.py 的跨平台兼容性（或明确标注 Unix-only）
2. 修复 collect_evidence.sh 的重复 Python 块
3. 在 README 中标注功能示例为"流程演示"而非已实现功能
4. 移除 GITHUB_UPLOAD_CHECKLIST.md 中的本地路径
5. `git rm --cached` 清理 verdict 历史文件

### P1 — 开源后一周内修复
6. 评估 "Mavis" 商标风险，考虑改名为 HTE
7. 创建独立 `src/` 目录，解除对 `.claude/` 的依赖
8. 整合迁移产物文档到 `docs/` 或 `HISTORY.md`
9. 添加 CONTRIBUTING.md
10. 将脚本重命名为 `hmte-*` 前缀

### P2 — 后续迭代
11. 优化 pretool_guard.sh 误报率
12. 添加 CHANGELOG.md
13. 清理文档中过度的 Claude Code 引用
14. 添加性能 benchmark 数据
15. e2e 测试的纯 Python JSON 验证

---

**审计完成。**
GLM-5.1 · 2026-05-27
