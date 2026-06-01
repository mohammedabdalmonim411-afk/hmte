# HTE v1.5 开发计划 (r3 收口修正版) - ✅ 已完成

> **版本定位**：Verifier 对抗验证与最小阻力合规评估  
> **开发原则**：轻量补强，不做平台化，只处理 P0/P1 问题  
> **基线版本**：v1.4.0 (commit 340fc49)  
> **修正版本**：r3 (2026-05-31)  
> **完成日期**：2026-06-01

## 完成状态

✅ **Phase 0**: 冻结 v1.4 基线  
✅ **Phase 1**: P0 - Verifier 自报字段交叉验证  
✅ **Phase 2**: P0 - Amendment / Goalpost Lock 收紧  
✅ **Phase 3**: P0 - Verifier 对抗测试集  
✅ **Phase 4**: P1 - Instruction Lint 规则扩展  
✅ **Phase 5**: P1 - attack-cases / red-team-results 沉淀  
✅ **Phase 6**: P1 - hmte-doctor 轻量自检  
✅ **Phase 7**: 集成测试与文档更新

## 测试结果

- ✅ e2e-core-workflow-test.sh: 8/8 通过
- ✅ e2e-anti-fake-test.sh: 12/12 通过
- ✅ e2e-lifecycle-test.sh: 16/16 通过
- ✅ e2e-p0-hardening-test.sh: 10/10 通过
- ✅ e2e-verifier-adversarial-test.sh: 12/12 通过
- ✅ test-protocol-lint.sh: 20/20 通过

**总计**: 78/78 测试通过

## 复杂度实际

- 新增代码：~3565 行（514 行修改 + 3051 行新文件）
- 新增文件：10 个（4 测试脚本 + 3 红队文档 + 3 规划文档）
- 新增依赖：0

## 修正历史
- r1: 初版
- r2: 技术修正（类型安全、协议规范）
- r3: 收口修正（豁免逻辑收紧、Amendment hash 归一化、测试 fixture 完整性）

## 严格不做事项
- ❌ 不做 SQLite / Web UI / LLM-as-Judge / 数字签名 / 插件市场
- ❌ 不做平台化 / 不重构大模块 / 不引入新依赖

## Phase 0：冻结 v1.4 基线
- 验证所有测试通过
- 记录 baseline commit
- 创建 docs/v1.5-baseline.md

## Phase 1：P0 - Verifier 自报字段交叉验证
- 增强 phase_gate.sh 验证逻辑（~130 行）
- P0 强制字段：independently_verified_files / evidence_paths / verification_method / risk_disposition / re_verification_conclusion
- 豁免条件收紧：docs_only / config_only / planning_only / review_only
- 类型安全：as_list() / as_dict() 归一化

## Phase 2：P0 - Amendment / Goalpost Lock 收紧
- Amendment hash 归一化：保持原顺序 + strip + 移除空字符串
- 新增 phase 绑定检查：必须有合法 amendment 且 hash 匹配
- Reason 长度：add_phase ≥20 / modify_criteria ≥30
- Release 模式：scope_impact=reduce / remove_phase → BLOCK

## Phase 3：P0 - Verifier 对抗测试集
- 新增 scripts/e2e-verifier-adversarial-test.sh
- one-bad-thing-per-case 原则
- 完整 runtime：session.json + phases.json + evidence + command log + verdict + receipt
- 真实项目文件 + command log output_tail

## Phase 4：P1 - Instruction Lint 规则扩展
- 扩展危险短语库（中英文各 ~15 条）
- 每个新增短语必须有测试 case
- 控制在 30 条以内

## Phase 5：P1 - attack-cases / red-team-results 沉淀
- 新增 docs/red-team-prompts.md / red-team-evaluation.md / red-team-results.md
- red-team-results.md 只做摘要表，不塞完整报告

## Phase 6：P1 - hmte-doctor 轻量自检
- 新增 scripts/hmte-doctor.sh
- 检查 git repo / bash / python3 / HTE scripts / .phase_control
- 只诊断，不自动修复

## 复杂度预算
- 新增代码：~840 行
- 新增文件：10 个
- 新增依赖：0

## 成功标准
- 所有 P0/P1 完成
- 所有测试通过（40/40 + 新增 Verifier adversarial）
- 不引入新依赖
- 不触碰严格不做事项

详细内容见完整计划文档。
