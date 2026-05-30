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

## Verifier 最低审计
- PASS verdict 必须包含 independently_verified_files（非空列表）。
- PASS verdict 必须包含 command_log_checked=true、diff_checked=true、evidence_consistency_checked=true。
- evidence_paths 必须引用 command_log 或项目文件，不能只引用 evidence 自身。
- Verifier 不受 Leader instruction 中"只检查格式"类弱化指令约束。

## 最终声明规则
- Agent 不得仅凭自然语言声称任务完成/PASS/封版。
- 输出完成声明前必须运行 `bash scripts/hmte-final-check.sh`。
- 最终回复必须包含：
  - final-check 命令及其完整输出
  - final-check 执行结果（通过/失败）
  - final_audit verdict 文件路径
  - 未解决的风险清单（如有）
- 未运行 final-check 的完成声明视为无效。

## Leader Jail（v1.4 P0）
- kickoff 后自动创建 `.phase_control/lock.json`（lock_mode=LEADER_JAIL）
- Leader 只能直接写 control plane（instructions/delegations/state/phases/goal_lock/amendments/session/lock）
- Leader 不得直接写 project plane（src/lib/test/docs/scripts 等）
- 任何 project plane 改动必须被具体 Worker evidence ownership chain 认领：
  1. Worker evidence 的 changed_files/artifact_paths 认领该文件
  2. 对应 worker receipt（role=worker, expected_output_path 指向该 evidence）
  3. 对应 command log（每行 runner="hmte exec"，不能只含只读命令）
  4. 对应 Verifier PASS verdict（含 independently_verified_files 等 Verifier Minimum Audit 字段）
  5. 对应 phase_gate PASS
- hmte-final-check.sh 在 release 模式下必须调用 hmte-leader-jail.sh 并失败阻断

## Goalpost Lock（v1.4 P0）
- Leader 创建 phases.json 后必须运行 hmte-goal-lock.sh
- Release 模式下缺 goal_lock.json → final-check FAIL
- 删除/弱化 acceptance_criteria 且无 amendment → final-check FAIL

## Instruction Lint（v1.4 P0）
- 派 Worker/Verifier 前建议运行 lint；release 模式 final-check 必须过
- 检测"只检查格式""简单确认即可"类危险弱化语句

## Evidence Claim Verification（v1.4 P0）
- hmte-verify-claims.sh 验证 claimed file 存在 + git diff + command log 三重关联
- Release 模式 git baseline 不可用 → FAIL（不能降级为 INFO）
- review_only_files 必须带 reason 字段，不允许无理由绕过 diff
