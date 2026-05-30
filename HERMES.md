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
Leader 写入 Worker instruction
  ↓
Worker 执行任务并生成 command log + evidence
  ↓
Leader 写入 Verifier instruction
  ↓
Verifier 审计 evidence 并生成 verdict
  ↓
phase_gate 检查阶段产物
  ↓
PASS → 下一阶段
FAIL → 返工
BLOCK → 升级处理
  ↓
所有阶段完成后运行 hmte-final-check.sh
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
