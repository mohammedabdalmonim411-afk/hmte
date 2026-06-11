# Handoff Contract v2

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Supersedes**: Handoff Contract v1 (v1.9)  
**Status**: Active  

---

## Overview

Handoff Contract v2 定义了 Leader / Worker / Verifier 之间的协作协议，重点是 **Leader-mediated Rework**：所有返工必须由 Leader 审批和创建，Verifier 只能输出 FAIL/BLOCK + recommendation。

---

## Core Principles

1. **Leader-mediated Rework** — 所有返工必须由 Leader 审批和创建
2. **No Direct Worker→Worker Handoff** — 禁止 Worker 直接把任务交给另一个 Worker
3. **No Direct Verifier→Worker Handoff** — 禁止 Verifier 直接把任务交给 Worker
4. **Plan-Grounded** — 所有 rework 必须引用原 plan item
5. **Timeout No Downgrade** — Worker timeout 后不得降级任务，只能等价重派、等价拆分、或 BLOCK

---

## Agent Roles

### Leader

**Responsibilities**:
- 创建 Worker instruction（引用 plan_ref）
- 创建 Verifier instruction（引用 audit_plan_ref）
- 审批 Verifier 的 rework recommendation
- 决定是否创建 next Worker attempt
- 决定是否 BLOCK 等用户决策

**Cannot Do**:
- 降级 plan item 要求（无 amendment）
- 简化 Worker 任务（无 plan 授权）
- 绕过 Verifier 审计

### Worker

**Responsibilities**:
- 执行 Leader 派发的任务
- 生成 evidence（引用 plan_item_ids）
- 记录 command log
- 报告 timeout / failure

**Cannot Do**:
- 直接把任务交给另一个 Worker
- 修改 plan item 要求
- 跳过 required tests（无 plan 授权）

### Verifier

**Responsibilities**:
- 审计 Worker evidence
- 检查 plan coverage
- 输出 verdict（PASS / FAIL / BLOCK）
- 提供 rework recommendation（如果 FAIL）

**Cannot Do**:
- 直接创建 next Worker attempt
- 直接把任务交给 Worker
- 修改 plan item 要求

---

## Handoff Flow

```
User Request
    ↓
Leader 创建 phases.json（引用 plan_hash + plan_item_ids）
    ↓
Leader 创建 Worker instruction（引用 plan_ref）
    ↓
Worker 执行（hmte exec）
    ↓
Worker 生成 evidence（引用 plan_item_ids）
    ↓
Leader 创建 Verifier instruction（引用 audit_plan_ref）
    ↓
Verifier 审计 evidence
    ↓
Verifier 输出 verdict
    ↓
    ├─ PASS → phase_gate → 下一 phase
    │
    ├─ FAIL + recommendation
    │       ↓
    │   Leader 审批 recommendation
    │       ↓
    │       ├─ 接受 → Leader 创建 rework contract（next attempt）
    │       └─ 拒绝 → BLOCK 等用户决策
    │
    └─ BLOCK → 等用户决策
```

---

## Rework Contract Schema

```json
{
  "rework_contract": {
    "original_phase_id": "phase_1",
    "original_attempt": 1,
    "verdict": "FAIL",
    "verifier_recommendation": "Add negative tests for plan coverage gate",
    "leader_decision": "REWORK",
    "new_attempt": 2,
    "plan_items_to_rework": ["S-001", "AC-001"],
    "max_rework_attempts": 3,
    "current_rework_count": 1,
    "rework_reason": "Verifier found missing negative tests",
    "plan_ref": {
      "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
      "plan_hash": "sha256:abc123...",
      "plan_item_ids": ["S-001", "AC-001"]
    }
  }
}
```

---

## Rework Rules

### 1. Verifier Output Rules

Verifier verdict 只能是以下三种：

| Verdict | 含义 | Leader Action |
|---------|------|---------------|
| PASS | 审计通过 | 进入下一 phase |
| FAIL | 审计失败，可修复 | 审批 recommendation，决定是否 rework |
| BLOCK | 审计失败，需用户决策 | 等用户决策 |

**Verifier 不能做的**：
- 不能直接创建 next Worker attempt
- 不能直接修改 plan item
- 不能绕过 Leader 审批

### 2. Leader Rework Decision Rules

Leader 收到 Verifier FAIL + recommendation 后，可以做以下决策：

| Decision | 含义 | Action |
|----------|------|--------|
| REWORK | 接受 recommendation | 创建 rework contract，引用原 plan item |
| REJECT | 拒绝 recommendation | BLOCK 等用户决策 |
| ESCALATE | 上报用户 | BLOCK 等用户决策 |

**Leader 不能做的**：
- 不能降级 plan item 要求（无 amendment）
- 不能简化 Worker 任务（无 plan 授权）
- 不能绕过 Verifier 审计

### 3. Rework Attempt Limit

- 默认最大 rework 次数：3
- 超过最大次数：BLOCK 等用户决策
- Rework 次数记录在 rework_contract.current_rework_count

### 4. Timeout Rework Rules

Worker timeout 后，Leader 可以做以下决策：

| Decision | 含义 | Allowed |
|----------|------|---------|
| 等价重派 | 重新派发相同任务 | ✅ Allowed |
| 等价拆分 | 拆成多个等价子任务 | ✅ Allowed |
| 降级任务 | 简化 plan item 要求 | ❌ Not Allowed（需 amendment） |
| BLOCK | 等用户决策 | ✅ Allowed |

**禁止的 timeout 处理**：
- 跳过 required tests（无 plan 授权）
- 用"核心测试"替代"完整测试"（无 plan 授权）
- 用"基本达成"替代 required evidence（无 plan 授权）

---

## Handoff Contract Verification

phase_gate 必须检查以下 handoff contract 合规性：

### Worker Instruction Checks

- [ ] Worker instruction 引用 plan_ref
- [ ] plan_ref.plan_hash 与 plan_lock 一致
- [ ] plan_ref.plan_item_ids 覆盖 plan 要求
- [ ] required_steps 不少于 plan 要求
- [ ] required_tests 不少于 plan 要求

### Verifier Instruction Checks

- [ ] Verifier instruction 引用 audit_plan_ref
- [ ] audit_plan_ref.plan_hash 与 plan_lock 一致
- [ ] audit_plan_ref.plan_item_ids_to_audit 覆盖 plan 要求
- [ ] evidence_files_to_read 不少于实际 evidence
- [ ] command_logs_to_read 不少于实际 command logs
- [ ] changed_files_to_review 不少于实际 changed_files

### Rework Contract Checks

- [ ] Rework contract 引用 original_phase_id
- [ ] Rework contract 引用 plan_items_to_rework
- [ ] plan_items_to_rework 与原 plan item 等价
- [ ] current_rework_count ≤ max_rework_attempts
- [ ] rework_reason 说明为什么需要 rework

---

## Prohibited Handoff Patterns

以下 handoff 模式禁止：

| Pattern | 原因 |
|---------|------|
| Worker → Worker | 违反三 Agent 骨架 |
| Verifier → Worker | 绕过 Leader 审批 |
| Leader 本地接管 | 绕过 Worker evidence |
| Verifier 自动创建 rework | 绕过 Leader 审批 |
| Worker 自决定 rework | 绕过 Verifier 审计 |

---

## Example: Full Rework Cycle

### 1. Initial Attempt

Leader 创建 Worker instruction:

```json
{
  "phase_id": "phase_1",
  "attempt": 1,
  "plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids": ["S-001", "AC-001", "T-001"]
  }
}
```

### 2. Worker Execution

Worker 执行并生成 evidence:

```json
{
  "phase_id": "phase_1",
  "attempt": 1,
  "plan_ref": {
    "plan_item_ids": ["S-001", "AC-001", "T-001"]
  },
  "changed_files": ["docs/PLAN_CONTRACT.md"],
  "tests_run": ["T-001"]
}
```

### 3. Verifier Audit

Leader 创建 Verifier instruction:

```json
{
  "phase_id": "phase_1",
  "attempt": 1,
  "audit_plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids_to_audit": ["S-001", "AC-001", "T-001"]
  }
}
```

Verifier 输出 verdict:

```json
{
  "verdict": "FAIL",
  "reason": "Missing negative test for plan item without ID",
  "recommendation": "Add negative test NT-001: plan_item_without_id_fails",
  "plan_item_ids_checked": ["S-001", "AC-001", "T-001"]
}
```

### 4. Leader Rework Decision

Leader 审批 recommendation，创建 rework contract:

```json
{
  "rework_contract": {
    "original_phase_id": "phase_1",
    "original_attempt": 1,
    "verdict": "FAIL",
    "verifier_recommendation": "Add negative test NT-001",
    "leader_decision": "REWORK",
    "new_attempt": 2,
    "plan_items_to_rework": ["S-001", "AC-001", "T-001"],
    "max_rework_attempts": 3,
    "current_rework_count": 1
  }
}
```

### 5. Rework Attempt

Leader 创建 Worker instruction for attempt 2:

```json
{
  "phase_id": "phase_1",
  "attempt": 2,
  "plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids": ["S-001", "AC-001", "T-001"]
  },
  "rework_contract_ref": {
    "original_attempt": 1,
    "rework_reason": "Add negative test NT-001"
  }
}
```

Worker 执行并生成 evidence（包含 NT-001），Verifier 审计通过。

---

## Success Criteria

- [ ] Leader 创建 Worker instruction（引用 plan_ref）
- [ ] Worker 生成 evidence（引用 plan_item_ids）
- [ ] Leader 创建 Verifier instruction（引用 audit_plan_ref）
- [ ] Verifier 输出 verdict（PASS / FAIL / BLOCK）
- [ ] 如果 FAIL，Leader 审批 recommendation
- [ ] 如果 rework，Leader 创建 rework contract
- [ ] 所有 rework 引用原 plan item
- [ ] 无 Worker → Worker handoff
- [ ] 无 Verifier → Worker handoff
- [ ] Timeout 不降级任务

---

**Last Updated**: 2026-06-10  
**Maintainer**: TAF Core Team
