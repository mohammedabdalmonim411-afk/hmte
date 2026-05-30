# Phase 6: 文档同步 (docs_sync)

## 目标
同步 README / HERMES / SKILL / CHANGELOG 文档，统一口径，反映 v1.4 新增的三个脚本和文件。

## 交付物
1. 更新 README.md
2. 更新 HERMES.md
3. 更新 src/skills/hmte/SKILL.md
4. 更新 CHANGELOG.md

## 统一口径要求
所有文档必须体现：
- HTE 是轻量级多 Agent 文件协议工作流框架
- 当前不是完整独立 Agent Runtime
- 真实 Worker / Verifier 执行依赖 Hermes delegate_task 或外部 Agent 环境
- receipt 默认是 INTENT_ONLY
- OBSERVED 需要真实 tool-call trace
- final_audit 当前手动触发
- v1.4 增加 protocol lint、claims、team-rules

## v1.4 新增内容
必须在文档中提及：
1. `scripts/hmte-lint-protocol.sh` - 协议检查脚本
2. `scripts/hmte-claims.sh` - 能力声明脚本
3. `.hmte/team-rules.md` - 团队规则文档

## 验收标准
- [ ] README.md 提到 v1.4 新增的三个脚本/文件
- [ ] HERMES.md 补充新增脚本说明
- [ ] SKILL.md 更新技能描述，反映 v1.4 能力
- [ ] CHANGELOG.md 记录 v1.4 变更
- [ ] 所有文档口径一致，无矛盾描述
- [ ] 不声称 HTE 是完整独立 Agent Runtime
- [ ] 不声称 OBSERVED 已经可用

## 执行方式
Worker 通过 `hmte exec` 执行文档更新任务。
