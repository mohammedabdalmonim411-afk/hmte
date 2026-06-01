# HTE Project Policy

本项目使用 HTE 进行结构化多 Agent 协作开发。

## 核心规则

1. **复杂任务必须使用 HTE 工作流**
   - 必须先创建 `.phase_control/phases.json`
   - 必须按 Leader → Worker → Verifier 流程推进
   - 必须通过 phase_gate 才能进入下一阶段

2. **角色边界**
   - Leader 负责规划阶段、维护状态、控制流程
   - Worker 负责执行阶段任务并产出 evidence
   - Verifier 负责独立审计并输出 verdict
   - Verifier 不修改业务实现代码
   - Worker 不自我放行

3. **阶段产物**
   - Worker 命令应通过 `hmte exec` 执行
   - 每个阶段应产出 command log
   - 每个阶段应产出 evidence bundle
   - 每个阶段应产出 verdict JSON
   - 阶段推进前必须通过 phase_gate

4. **文件归属**
   - `.phase_control/phases.json`：Leader
   - `.phase_control/instructions/`：Leader
   - `.phase_control/delegations/`：Leader
   - `.phase_control/logs/`：hmte exec
   - `.phase_control/evidence/`：Worker
   - `.phase_control/verdicts/`：Verifier
   - `.phase_control/state.json`：Leader / orchestrator

## 工作流

```text
User Request
  ↓
Leader 创建 phases.json
  ↓
Leader 运行 hmte-goal-lock.sh（锁定验收标准）
  ↓
Leader 写入 Worker instruction（需要先过 Instruction Lint）
  ↓
Worker 执行任务并生成 command log + evidence
  ↓
hmte-verify-claims.sh 验证 evidence claims（P0-3）
  ↓
Leader 写入 Verifier instruction
  ↓
Verifier 审计 evidence 并生成 verdict（须含 Verifier Minimum Audit 字段）
  ↓
phase_gate 检查阶段产物（含 P0-4 Verifier Minimum Audit）
  ↓
PASS → 下一阶段
FAIL → 返工
BLOCK → 升级处理
  ↓
所有阶段完成后运行 hmte-final-check.sh（含 Leader Jail + Goalpost Lock + 全 P0 检查）
  ↓
Final Audit (Release Auditor)
  ↓
声明完成（须附 final-check 输出 + verdict 路径）
```

## 使用范围

适合使用 HTE 的任务：

- 多阶段功能开发
- 复杂重构
- 需要审计和验收的工程任务
- 需要明确质量门禁的任务

可以不使用 HTE 的任务：

- 简单文本修改
- 单文件小修
- 临时性探索
- 非工程化问答

## 最终声明规则

Agent 在输出"完成/PASS/封版/全部通过"声明前必须运行 `bash scripts/hmte-final-check.sh`。

最终回复必须包含：
1. final-check 命令输出
2. 执行结果（exit code）
3. final_audit verdict 路径
4. 未解决风险列表

未运行 final-check 的完成声明视为无效。

## v1.5 P0 加固机制

以下机制从 v1.5 开始强制执行（release 模式下均为 FAIL 级阻断）：

| 机制 | 脚本 | 作用 |
|------|------|------|
| Leader Jail | `hmte-leader-jail.sh` | 验证 Leader 未越权写项目面文件（kickoff 后自动激活 lock.json） |
| Goalpost Lock | `hmte-goal-lock.sh` | SHA256 锁定验收标准，检测后续弱化/删除（release 模式缺锁→FAIL） |
| Instruction Lint | `hmte-lint-instructions.sh` | 检测"只检查格式"类危险弱化语句 |
| Evidence Claim Verification | `hmte-verify-claims.sh` | 验证每个 claimed file 真实存在 + 在 git diff 中 + 在 command log 中 |
| Verifier Minimum Audit | `phase_gate.sh` (内嵌) | PASS verdict 必须含 P0 必需字段（详见下方） |
| Final Check v2 | `hmte-final-check.sh` | 完整链路（7-file 完整性 + 全部 P0 检查 + Leader Jail） |

### Verifier Minimum Audit（P0-4）

从 v1.5 开始，所有 PASS verdict 必须包含以下 P0 必需字段：

1. **verification_method**（字符串，非空）
   - 说明验证方法（如 `cross_check`, `manual_review`, `automated_test`）

2. **risk_disposition**（数组，可为空）
   - 每个 unresolved_risk 必须有对应的 disposition 条目
   - 每个条目必须包含：`risk`, `disposition`, `reason`
   - `reason` 长度 >= 10 字符

3. **re_verification_conclusion**（字符串，>= 20 字符）
   - 不能是 `ok`, `pass`, `done`, `yes`, `good`, `证据支持 PASS` 等敷衍内容
   - 必须说明复核了哪些证据、为何支持 PASS

4. **independently_verified_files**（数组，非空）
   - 必须列出实际验证过的文件
   - 文件必须真实存在

5. **evidence_paths**（数组，非空）
   - 必须同时包含 evidence 和 command log 路径
   - 示例：`[".phase_control/evidence/phase_a_attempt_1.json", ".phase_control/logs/phase_a_attempt_1.commands.jsonl"]`

6. **criteria_passed[].evidence**（字符串，非空）
   - 不能是 `ok`, `pass`, `done`, `yes`, `good` 等敷衍内容
   - 必须引用具体证据路径或命令日志条目

7. **command_log_checked / diff_checked / evidence_consistency_checked**（布尔值，必须为 true）

缺少任何 P0 字段或字段值不符合要求，phase_gate 将 FAIL。

### Leader Jail 详细约束

- Leader 只能直接写 control plane: `.phase_control/instructions/`, `delegations/`, `state.json`, `phases.json`, `goal_lock.json`, `amendments/`, `session.json`, `lock.json`
- Leader 不得直接写 project plane（`src/`, `lib/`, `test/`, `docs/`, `scripts/` 等）
- 任何 project plane 改动必须满足完整 ownership chain：
  1. 被具体 Worker evidence 的 `changed_files` 或 `artifact_paths` 认领
  2. 有对应 worker receipt（`role=worker`, `expected_output_path` 指向该 evidence）
  3. 有对应 command log（每行 `runner="hmte exec"`）
  4. 有对应 Verifier PASS verdict（含 Verifier Minimum Audit 字段）
  5. 对应 `phase_gate` PASS
