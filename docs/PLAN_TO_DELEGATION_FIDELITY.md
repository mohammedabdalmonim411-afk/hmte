# Plan-to-Delegation Fidelity

**Version**: 1.0  
**Status**: Stable  
**Part of**: TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance  

---

## Purpose

解决 **Leader 阉割计划书** 的问题。

Worker instruction 必须引用 plan item，不得少派、改派、简派。

---

## Principles

1. **Full Coverage** — Worker instruction 不得少派任务
2. **No Substitution** — Worker instruction 不得改派任务（如把集成测试改成单元测试）
3. **No Simplification** — Worker instruction 不得简派任务（如把完整覆盖率报告改成核心测试）
4. **Timeout Policy** — Worker timeout 后可等价重派、等价拆分、或 BLOCK，不得降级
5. **Amendment Required** — 降级验收标准必须有 amendment

---

## Worker Instruction Schema

Worker instruction 必须包含 `plan_ref`：

```json
{
  "phase_id": "phase_1",
  "goal": "实现 Plan Contract",
  "plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids": ["S-001", "AC-001", "AC-002", "T-001"],
    "required_steps": [
      "实现 Plan Contract 标准化",
      "实现 Plan Contract 验证脚本",
      "验证所有 plan items 有 ID"
    ],
    "required_tests": ["T-001"],
    "allowed_scope": ["docs/", "scripts/"],
    "forbidden_scope": [".phase_control/", "dogfood_regression/"],
    "non_waivable_requirements": [
      "所有 P0 项必须完成",
      "所有负向测试必须通过",
      "plan_hash 必须一致"
    ]
  },
  "context": "...",
  "instruction": "..."
}
```

---

## Fidelity Rules

### 1. Full Coverage

Worker instruction 的 `plan_item_ids` 必须覆盖 locked plan 中该 phase 的所有 items。

**检查方法**：
```
locked_plan.phases[phase_id].plan_items ⊆ worker_instruction.plan_ref.plan_item_ids
```

如果 `plan_item_ids` 少于 locked plan 要求，fidelity check FAIL。

### 2. No Substitution

原计划要求 "集成测试"，不能改成 "单元测试"。

原计划要求 "完整覆盖率报告"，不能改成 "核心测试"。

### 3. No Simplification

原计划要求 "所有 P0 验收标准"，不能只派 "部分验收标准"。

### 4. Timeout Policy

Worker timeout 后：

✅ **允许**：
- 等价重派（相同任务，重新执行）
- 等价拆分（拆成多个子任务，总和等价）
- BLOCK 等用户决策

❌ **禁止**：
- 降级验收标准（无 amendment）
- 跳过 required tests（无 amendment）
- 简化 required artifacts（无 amendment）

### 5. Amendment Required

如果需要降级验收标准（如因环境限制无法执行某项测试），必须：

1. 创建 amendment
2. reason ≥ 100 字符，说明降级原因、影响范围、风险评估
3. human 批准
4. 更新 plan lock

---

## Evidence Schema

Worker evidence 必须包含 `plan_ref` 和 `evidence_by_plan_item`：

```json
{
  "phase_id": "phase_1",
  "plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids": ["S-001", "AC-001", "AC-002", "T-001"]
  },
  "evidence_by_plan_item": {
    "S-001": {
      "changed_files": ["docs/PLAN_CONTRACT.md"],
      "command_logs": ["phase_1_attempt_1.commands.jsonl"],
      "tests": ["T-001"],
      "artifacts": ["plan_contract_schema.json"],
      "artifact_hash": "sha256:...",
      "verifier_checked": true
    },
    "AC-001": {
      "changed_files": ["scripts/hmte-plan-contract.sh"],
      "command_logs": ["phase_1_attempt_1.commands.jsonl"],
      "tests": [],
      "artifacts": [],
      "verifier_checked": true
    }
  },
  "tests_run": ["T-001"],
  "tests_failed": [],
  "tests_skipped": [],
  "tests_timed_out": [],
  "changed_files": ["docs/PLAN_CONTRACT.md", "scripts/hmte-plan-contract.sh"],
  "command_logs": ["phase_1_attempt_1.commands.jsonl"]
}
```

---

## Plan-to-Evidence Anchoring

Evidence 不能只写 `plan_item_ids: ["S-001", "AC-001"]`，必须有 **item-level evidence mapping**。

### Anchoring Rules

1. 没有 `evidence_by_plan_item`，不算覆盖
2. 没有 `changed_files` / `command_logs` / `tests` / `artifacts` 中至少一种有效锚点，不算覆盖
3. 文档类 plan item 要有文档路径和段落锚点
4. 测试类 plan item 要有测试命令、测试名、exit code、原始输出或报告路径
5. 代码类 plan item 要有 `changed_files` 和验证命令

---

## Usage

### Check Fidelity

```bash
# 检查 Worker instruction 是否引用 plan_ref
bash scripts/hmte-check-fidelity.sh \
  --instruction .phase_control/instructions/phase_1.json \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-lock .phase_control/plan_lock.json

# 检查 evidence 是否覆盖 plan items
bash scripts/hmte-check-fidelity.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-lock .phase_control/plan_lock.json
```

---

## Integration with phase_gate

phase_gate 必须检查：

1. ✅ Worker instruction 包含 `plan_ref`
2. ✅ `plan_ref.plan_hash` 与 locked hash 一致
3. ✅ `plan_ref.plan_item_ids` 覆盖 locked plan 要求
4. ✅ Worker evidence 包含 `plan_ref`
5. ✅ Worker evidence 包含 `evidence_by_plan_item`
6. ✅ `evidence_by_plan_item` 每个 item 都有有效锚点

如果任一检查失败，phase_gate 必须 FAIL。

---

## Negative Test Cases

| ID | Test | Expected |
|----|------|----------|
| PD001 | worker_instruction_missing_plan_ref | FAIL |
| PD002 | leader_simplifies_worker_task_from_plan | FAIL |
| PD003 | worker_timeout_leader_downgrades_required_test | BLOCK |
| PD004 | integration_tests_skipped_without_amendment | BLOCK |
| PD005 | coverage_report_replaced_by_core_tests | FAIL |
| PD006 | previous_phase_tests_used_as_substitute | FAIL |
| PD007 | leader_simplifies_plan_item_into_smaller_task | FAIL |
| PD008 | integration_tests_skipped_with_fake_amendment | FAIL |
| PD009 | vague_plan_item_rejected | FAIL |
| PD010 | phases_json_drops_locked_plan_item | FAIL |
| PD011 | timeout_resplit_drops_required_test | BLOCK |
| PD012 | worker_instruction_claims_full_plan_but_steps_partial | FAIL |

---

## Related Documents

- `docs/PLAN_CONTRACT.md` - Plan Contract 设计
- `docs/PLAN_LOCK.md` - Plan Lock 设计
- `docs/VERIFIER_MANDATE.md` - Verifier Mandate Contract 设计
- `docs/PLAN_COVERAGE_GATE.md` - Plan Coverage Gate 设计
