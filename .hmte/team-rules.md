# HTE Team Rules

## 通用规则
- 所有 Worker 命令必须通过 hmte exec。
- evidence 必须包含 command_log_path。
- PASS verdict 的 criteria_failed 必须为空。
- final_audit 必须检查 README / HERMES / SKILL / scripts 口径一致。

## 角色边界
- Leader 不直接执行 Worker 实现任务。
- Worker 不写 verdict。
- Verifier 不修改业务代码。
- Release Auditor 不修复问题，只做通盘审计。

## 能力边界
- receipt 默认是 INTENT_ONLY。
- OBSERVED 需要真实 tool-call trace。
- HTE 当前是文件协议工作流，不是完整独立 Agent Runtime。

## 最终声明规则
- Agent 不得仅凭自然语言声称任务完成/PASS/封版。
- 输出完成声明前必须运行 `bash scripts/hmte-final-check.sh`。
- 最终回复必须包含：
  - final-check 命令及其完整输出
  - final-check 执行结果（通过/失败）
  - final_audit verdict 文件路径
  - 未解决的风险清单（如有）
- 未运行 final-check 的完成声明视为无效。
