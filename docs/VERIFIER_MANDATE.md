# Verifier Mandate Contract

**Version**: 1.0  
**Status**: Stable  
**Part of**: TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance  

---

## Purpose

解决 **Leader 给 Verifier 放水** 和 **Verifier 礼貌型 PASS** 的问题。

Verifier instruction 必须引用 audit plan，禁止 summary-only review。

---

## Principles

1. **Full Audit Scope** — Verifier 必须审计所有 plan items
2. **Evidence-Based** — Verifier 必须检查 evidence、command logs、changed files
3. **No Shortcuts** — 禁止 summary-only review、spot check only、skip command log
4. **Independent Verification** — Verifier 独立检查，不信任 Worker 声明
5. **Zero-Finding Needs Justification** — Verifier PASS 必须解释为什么没有问题

---

## Verifier Instruction Schema

Verifier instruction 必须包含 `audit_plan_ref`：

```json
{
  "phase_id": "phase_1",
  "audit_plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids_to_audit": ["S-001", "AC-001", "AC-002", "T-001"],
    "acceptance_criteria_to_check": ["AC-001", "AC-002"],
    "required_tests_to_check": ["T-001"],
    "evidence_files_to_read": [
      ".phase_control/evidence/phase_1_attempt_1.json"
    ],
    "command_logs_to_read": [
      ".phase_control/logs/phase_1_attempt_1.commands.jsonl"
    ],
    "changed_files_to_review": [
      "docs/PLAN_CONTRACT.md",
      "scripts/hmte-plan-contract.sh"
    ],
    "risk_items_to_check": ["R-001"],
    "forbidden_shortcuts": [
      "summary-only review",
      "spot check only",
      "skip command log",
      "trust Worker claim",
      "obvious issues only",
      "quick review only",
      "ignore slow tests",
      "ignore skipped tests"
    ]
  },
  "context": "...",
  "instruction": "..."
}
```

---

## Mandate Rules

### 1. Full Audit Scope

Verifier instruction 的 `plan_item_ids_to_audit` 必须覆盖 locked plan 中该 phase 的所有 items。

**检查方法**：
```
locked_plan.phases[phase_id].plan_items ⊆ verifier_instruction.audit_plan_ref.plan_item_ids_to_audit
```

如果 `plan_item_ids_to_audit` 少于 locked plan 要求，mandate check FAIL。

### 2. Evidence-Based Audit

Verifier 必须检查：
- ✅ 所有 `evidence_files_to_read`
- ✅ 所有 `command_logs_to_read`
- ✅ 所有 `changed_files_to_review`
- ✅ 所有 `required_tests_to_check`

### 3. No Shortcuts

禁止以下审计弱化指令：

| 禁止短语 | 原因 |
|----------|------|
| "summary-only review" | 只做摘要审查，不做详细检查 |
| "spot check only" | 只抽查，不全面检查 |
| "skip command log" | 跳过命令日志检查 |
| "trust Worker claim" | 信任 Worker 声明，不独立验证 |
| "obvious issues only" | 只检查明显问题 |
| "quick review only" | 快速审查，不深入 |
| "ignore slow tests" | 忽略慢测试 |
| "ignore skipped tests" | 忽略跳过的测试 |

### 4. Audit Scope Hard Rules

**完整审计范围** = locked plan required items + evidence manifest + command log manifest + changed_files/diff + anomaly ledger

**Leader instruction 只能增加上下文，不能缩小审计范围**。

**实际工件强制审计**：
- Verifier 必须审计所有 actual changed_files（来自 git diff / evidence.changed_files）
- Verifier 必须审计所有 actual command_logs（来自 .phase_control/logs/）
- Verifier 必须审计所有 actual tests_run（来自 evidence.tests_run）

### 5. review_trail Required

Verifier verdict 必须包含 `review_trail`，记录每个 plan item 的检查路径和发现。

---

## Verdict Schema

Verifier verdict 必须包含：

```json
{
  "phase_id": "phase_1",
  "verdict": "PASS",
  "audit_plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids_to_audit": ["S-001", "AC-001", "AC-002", "T-001"]
  },
  "plan_item_ids_checked": ["S-001", "AC-001", "AC-002", "T-001"],
  "review_trail": [
    {
      "plan_item_id": "S-001",
      "checked_file": "docs/PLAN_CONTRACT.md",
      "checked_command_log": ".phase_control/logs/phase_1_attempt_1.commands.jsonl",
      "evidence_ref": ".phase_control/evidence/phase_1_attempt_1.json",
      "verifier_finding": "PASS"
    },
    {
      "plan_item_id": "AC-001",
      "checked_file": "scripts/hmte-plan-contract.sh",
      "checked_command_log": ".phase_control/logs/phase_1_attempt_1.commands.jsonl",
      "evidence_ref": ".phase_control/evidence/phase_1_attempt_1.json",
      "verifier_finding": "PASS"
    }
  ],
  "zero_finding_justification": {
    "checked_plan_items": ["S-001", "AC-001", "AC-002", "T-001"],
    "checked_files": ["docs/PLAN_CONTRACT.md", "scripts/hmte-plan-contract.sh"],
    "checked_command_logs": ["phase_1_attempt_1.commands.jsonl"],
    "checked_tests": ["T-001"],
    "checked_anomalies": [],
    "why_no_p0": "All P0 plan items covered by evidence, tests pass, no anomalies",
    "why_no_p1": "No P1 risks identified in code review and test execution",
    "residual_risks": []
  },
  "findings": []
}
```

---

## Usage

### Check Verifier Instruction

```bash
# 检查 Verifier instruction 是否引用 audit_plan_ref
bash scripts/hmte-check-mandate.sh \
  --instruction .phase_control/verifier_instructions/phase_1.json \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-lock .phase_control/plan_lock.json
```

### Check Verifier Verdict

```bash
# 检查 Verifier verdict 是否完整
bash scripts/hmte-check-mandate.sh \
  --verdict .phase_control/verdicts/phase_1_verdict.json \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --check-zero-finding
```

---

## Integration with phase_gate

phase_gate 必须检查：

1. ✅ Verifier instruction 包含 `audit_plan_ref`
2. ✅ `audit_plan_ref.plan_hash` 与 locked hash 一致
3. ✅ `audit_plan_ref.plan_item_ids_to_audit` 覆盖 locked plan 要求
4. ✅ Verifier instruction 不包含 `forbidden_shortcuts`
5. ✅ Verifier verdict 包含 `plan_item_ids_checked`
6. ✅ Verifier verdict 包含 `review_trail`
7. ✅ Verifier verdict 包含 `zero_finding_justification`（如果 verdict = PASS）

如果任一检查失败，phase_gate 必须 FAIL。

---

## Negative Test Cases

| ID | Test | Expected |
|----|------|----------|
| VM001 | verifier_instruction_missing_audit_plan_ref | FAIL |
| VM002 | verifier_instruction_omits_p0_plan_item | FAIL |
| VM003 | verifier_instruction_says_summary_only | FAIL |
| VM004 | verifier_instruction_skips_command_log | FAIL |
| VM005 | parallel_verifier_instruction_missing_one_shard | FAIL |
| VM006 | verifier_rubber_stamp_pass | FAIL |
| VM007 | verifier_instruction_omits_required_plan_item | FAIL |
| VM008 | verifier_instruction_limits_review_to_summary_only | FAIL |
| VM009 | verifier_mandate_omits_changed_file | FAIL |
| VM010 | verifier_instruction_restricts_to_summary_by_synonym | FAIL |

---

## Related Documents

- `docs/PLAN_CONTRACT.md` - Plan Contract 设计
- `docs/PLAN_LOCK.md` - Plan Lock 设计
- `docs/PLAN_TO_DELEGATION_FIDELITY.md` - Plan-to-Delegation Fidelity 设计
- `docs/ZERO_FINDING.md` - Zero-Finding Justification 设计
