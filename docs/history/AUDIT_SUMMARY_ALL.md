# HMTE 项目 - 6 次审计汇总报告

**汇总日期**: 2026-05-27  
**审计次数**: 6 次  
**审计模型**: Claude Opus 4-7 (x2), DeepSeek V4 Pro, 小米 Mimo V2.5 Pro, GLM-5.1, Mimo V2.5 Pro

---

## 🔴 严重问题（CRITICAL）- 2 个

### 1. write_state.py 使用 fcntl，Windows 不兼容
**位置**: `.claude/skills/mavis-team-engine/scripts/write_state.py` 行 7  
**发现者**: GLM-5.1  
**问题**: `import fcntl` 在 Windows 上不存在，脚本直接崩溃  
**影响**: Windows 用户无法使用状态管理功能  
**修复**: 使用跨平台的文件锁方案（msvcrt 或 filelock 库）

### 2. collect_evidence.sh 有重复的 Python 代码块
**位置**: `.claude/skills/mavis-team-engine/scripts/collect_evidence.sh`  
**发现者**: GLM-5.1  
**问题**: 约 50 行 Python 代码重复执行  
**影响**: 性能浪费，代码维护困难  
**修复**: 删除重复代码块

---

## 🔴 高优先级（HIGH）- 8 个

### 3. "Mavis" 商标风险未充分说明
**位置**: README.md, LEGAL_REVIEW.md  
**发现者**: GLM-5.1  
**问题**: "Mavis" 是 MiniMax 的产品名，项目全称 "Hermes Mavis Team Engine" 直接使用，构成商标性使用  
**影响**: 法律风险，可能被 MiniMax 主张商标侵权  
**修复**: 改名为 "Hermes Team Engine (HTE)" 或咨询律师

### 4. README.md 包含虚构的功能演示
**位置**: README.md 行 242-374  
**发现者**: GLM-5.1  
**问题**: "User Authentication" 示例写成已完成事实，但项目无任何认证代码  
**影响**: 误导用户  
**修复**: 标注为"示例流程"而非"已实现功能"

### 5. "7x token" 性能数据无依据
**位置**: README.md 行 563  
**发现者**: GLM-5.1  
**问题**: 无 benchmark 支撑  
**影响**: 误导用户对成本的预期  
**修复**: 标注为"估算值"或删除

### 6. 时间数据无依据
**位置**: README.md 行 577-579  
**发现者**: GLM-5.1  
**问题**: "2-5 minutes" 等数据无测试支撑  
**影响**: 误导用户对性能的预期  
**修复**: 标注为"估算值"或删除

### 7. Agent 定义使用 Claude Code 语法，与 Hermes 不匹配
**位置**: `.claude/agents/*.md`  
**发现者**: Mimo V2.5 Pro  
**问题**: 使用 `subagent_type` 等 Claude Code 语法，Hermes 的 `delegate_task` 不支持  
**影响**: 核心架构行为与文档描述不符  
**修复**: 更新 agent 定义为 Hermes 兼容格式，或添加说明

### 8. Hooks 在 Hermes 中不会自动执行
**位置**: `.claude/hooks/*.sh`  
**发现者**: Mimo V2.5 Pro  
**问题**: Hooks 未在 SKILL.md 中注册，安全防护完全不生效  
**影响**: 安全功能失效  
**修复**: 在 SKILL.md 中注册 hooks 或添加说明

### 9. GitHub clone URL 可能不存在
**位置**: README.md 多处  
**发现者**: Mimo V2.5 Pro  
**问题**: 仓库可能未公开或 URL 错误  
**影响**: 用户无法 clone  
**修复**: 验证 URL 或使用占位符

### 10. .claude/ 目录是安装脚本的唯一数据源
**位置**: install-to-hermes.sh  
**发现者**: GLM-5.1  
**问题**: `SOURCE_DIR=".claude/skills/mavis-team-engine/"`，删除 .claude/ 会破坏安装  
**影响**: 架构混乱  
**修复**: 创建独立的 `src/` 目录

---

## 🟡 中优先级（MEDIUM）- 13 个

### 11. 统计数据不准确
**位置**: README.md 行 737-738  
**发现者**: 所有审计员  
**问题**: 声称 39 文件/5,700 行，实际 41-56 文件/6,318-6,769 行  
**修复**: 更新为准确数据

### 12. 统计数据四处矛盾
**位置**: README.md, FINAL_REPORT.md, VERIFICATION_REPORT.md  
**发现者**: Mimo V2.5 Pro  
**问题**: 四处数据不一致  
**修复**: 统一为最新数据

### 13. 仓库名称不一致
**位置**: 多处  
**发现者**: 小米 Mimo V2.5 Pro  
**问题**: README 使用 `mavis-team-engine`，但项目已改名 HMTE  
**修复**: 添加说明或统一名称

### 14. 技能名称不一致
**位置**: SKILL.md  
**发现者**: 小米 Mimo V2.5 Pro  
**问题**: `name: mavis-team-engine` vs 安装到 `hmte/`  
**修复**: 统一为 `hmte`

### 15. VERIFICATION_REPORT.md 统计数据过时
**位置**: VERIFICATION_REPORT.md 行 21  
**发现者**: DeepSeek V4 Pro  
**问题**: 无时间戳说明  
**修复**: 添加时间戳

### 16. 安装路径说明不够明确
**位置**: install-to-hermes.sh  
**发现者**: 小米 Mimo V2.5 Pro  
**问题**: 用户不知道从哪里复制文件  
**修复**: 添加完整安装说明

### 17. Windows 兼容性未提前说明
**位置**: README.md Prerequisites  
**发现者**: Mimo V2.5 Pro  
**问题**: 未警告 Windows 用户  
**修复**: 添加 Windows 兼容性说明

### 18. worktree 隔离不存在
**位置**: phase-executor.md  
**发现者**: Mimo V2.5 Pro  
**问题**: 声称 `isolation: worktree`，但 Hermes 无此功能  
**修复**: 删除或标注为 Claude Code 特性

### 19. Agent frontmatter 使用 Claude Code 术语
**位置**: `.claude/agents/*.md`  
**发现者**: GLM-5.1  
**问题**: `tools`, `permissionMode` 等字段 Hermes 不支持  
**修复**: 添加说明

### 20. 文档碎片化严重
**位置**: 根目录  
**发现者**: GLM-5.1  
**问题**: 12 个顶层 .md 文件，8 个是迁移产物  
**修复**: 整合到 `docs/` 或 `HISTORY.md`

### 21. 第三方 GitHub 用户名硬编码
**位置**: 多处  
**发现者**: GLM-5.1  
**问题**: `YOUR_USERNAME` 硬编码  
**修复**: 使用占位符或组织名

### 22. Quick Start cp 命令使用占位符路径
**位置**: README.md  
**发现者**: Mimo V2.5 Pro  
**问题**: `/path/to/` 占位符  
**修复**: 给出明确路径

### 23. Manual Testing 步骤编号错误
**位置**: README.md 行 549-557  
**发现者**: Mimo V2.5 Pro  
**问题**: 编号倒退和重复  
**修复**: 修正编号

---

## 🟢 低优先级（LOW）- 8 个

### 24-31. 缺少社区文档、模板占位符、历史文档引用等
**发现者**: 多位审计员  
**影响**: 不影响核心功能  
**修复**: 可选

---

## 📊 问题统计

| 优先级 | 数量 | 占比 |
|--------|------|------|
| 🔴 严重 | 2 | 6% |
| 🔴 高 | 8 | 26% |
| 🟡 中 | 13 | 42% |
| 🟢 低 | 8 | 26% |
| **总计** | **31** | **100%** |

---

## 🎯 修复策略

### 阶段 1: 严重问题（必须修复）
1. write_state.py Windows 兼容
2. collect_evidence.sh 删除重复代码

### 阶段 2: 高优先级（强烈建议）
3-10. 商标风险、虚构示例、架构不匹配等

### 阶段 3: 中优先级（建议修复）
11-23. 统计数据、名称一致性、文档完善等

### 阶段 4: 低优先级（可选）
24-31. 社区文档、占位符等

---

## 🚀 下一步

启动 Mavis 工作流，按阶段修复所有问题。
