# Zero-Finding Justification

**Version**: 1.0  
**Status**: Stable  
**Part of**: TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance  

---

## Purpose

如果 Verifier 没审计出问题，**必须解释为什么没有问题**。

防止 **多 phase 连续零发现** 成为审计质量风险。

---

## Principles

1. **Zero Finding Needs Evidence** — 零发现需要证据锚点，不能只写"all good"
2. **Evidence Anchor Required** — 必须引用具体检查的文件、命令日志、测试
3. **Residual Risks Must Be Listed** — 必须列出剩余风险
4. **Consecutive Zero Findings Trigger Review** — 连续 3 个 phase 零发现需说明

---

## Schema

Verifier verdict 的 `zero_finding_justification` 必须包含：

```json
{
  "zero_finding_justification": {
    "checked_plan_items": ["S-001", "S-002", "AC-001"],
    "checked_files": [
      "docs/PLAN_CONTRACT.md",
      "scripts/hmte-plan-contract.sh"
    ],
    "checked_command_logs": ["phase_1_attempt_1.commands.jsonl"],
    "checked_tests": ["T-001", "T-002"],
    "checked_anomalies": [],
    "why_no_p0": "All P0 plan items covered by evidence (see checked_files), tests pass (see checked_tests), no anomalies in ledger",
    "why_no_p1": "No P1 risks identified in code review (see checked_files) and test execution (see checked_tests)",
    "residual_risks": [
      "Documentation could be more detailed",
      "Edge case coverage could be improved"
    ]
  }
}
```

---

## Required Fields

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `checked_plan_items` | Yes | array | 检查的 plan item IDs |
| `checked_files` | Yes | array | 检查的文件路径 |
| `checked_command_logs` | Yes | array | 检查的命令日志 |
| `checked_tests` | Yes | array | 检查的测试名称 |
| `checked_anomalies` | No | array | 检查的异常 IDs |
| `why_no_p0` | Yes | string | 为什么没有 P0 问题（必须引用证据） |
| `why_no_p1` | Yes | string | 为什么没有 P1 问题（必须引用证据） |
| `residual_risks` | Yes | array | 剩余风险列表 |

---

## Rules

### 1. Evidence Anchor Required

不能只写：
- ❌ "all good"
- ❌ "no issue"
- ❌ "checked"
- ❌ "pass"

必须包含证据锚点：
- ✅ `checked_plan_items` 列出所有检查的 plan items
- ✅ `checked_files` 列出所有检查的文件
- ✅ `checked_command_logs` 列出所有检查的命令日志
- ✅ `checked_tests` 列出所有检查的测试
- ✅ `why_no_p0` / `why_no_p1` 必须引用具体证据

### 2. Not Keywords-Based

不要用"最小字数"作为主要标准，**证据锚点比字数重要**。

### 3. Consecutive Zero Findings Detection

```
IF 连续 3 个 phase 都是 PASS 且 zero_finding_justification 不完整：
  → 标记为审计质量风险
  → release_gate 可以 PENDING（需人工确认）
```

---

## Justification Quality Levels

| Level | Criteria | Gate Decision |
|-------|----------|---------------|
| **Good** | All required fields present with evidence anchors | PASS |
| **Acceptable** | All required fields present, but anchors minimal | PASS with warning |
| **Poor** | Missing required fields or no evidence anchors | FAIL |
| **Suspicious** | Consecutive 3+ phases with minimal justification | PENDING (needs human review) |

---

## Usage

### Check Zero-Finding Justification

```bash
# 检查 zero-finding justification
bash scripts/hmte-check-mandate.sh \
  --verdict .phase_control/verdicts/phase_1_verdict.json \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --check-zero-finding
```

---

## Integration with phase_gate

phase_gate 必须检查（如果 verdict = PASS）：

1. ✅ Verdict 包含 `zero_finding_justification`
2. ✅ `zero_finding_justification` 包含所有 required fields
3. ✅ `checked_plan_items` 非空
4. ✅ `checked_files` 非空
5. ✅ `checked_command_logs` 非空
6. ✅ `checked_tests` 非空
7. ✅ `why_no_p0` 引用证据
8. ✅ `why_no_p1` 引用证据

如果任一检查失败，phase_gate FAIL。

---

## Integration with release_gate

release_gate 必须检查：

1. ✅ 连续零发现检测
2. ✅ 如果连续 3 个 phase 零发现无解释，release_gate PENDING

---

## Example: Good Justification

```json
{
  "zero_finding_justification": {
    "checked_plan_items": ["S-001", "AC-001", "AC-002", "T-001"],
    "checked_files": [
      "docs/PLAN_CONTRACT.md",
      "scripts/hmte-plan-contract.sh"
    ],
    "checked_command_logs": ["phase_1_attempt_1.commands.jsonl"],
    "checked_tests": ["T-001"],
    "checked_anomalies": [],
    "why_no_p0": "All P0 plan items (S-001, AC-001, AC-002) covered by evidence in docs/PLAN_CONTRACT.md and scripts/hmte-plan-contract.sh. Test T-001 passed with exit code 0 in phase_1_attempt_1.commands.jsonl. No anomalies in ledger.",
    "why_no_p1": "Code review of scripts/hmte-plan-contract.sh shows proper error handling. No P1 risks identified in command execution logs.",
    "residual_risks": [
      "Edge case: Plan items without ID not yet tested",
      "Performance: Large plan files not benchmarked"
    ]
  }
}
```

---

## Example: Poor Justification (FAIL)

```json
{
  "zero_finding_justification": {
    "checked_plan_items": [],
    "checked_files": [],
    "checked_command_logs": [],
    "checked_tests": [],
    "why_no_p0": "Everything looks good",
    "why_no_p1": "No issues found",
    "residual_risks": []
  }
}
```

**Why it fails**:
- ❌ All arrays are empty (no evidence anchors)
- ❌ `why_no_p0` / `why_no_p1` don't reference specific evidence
- ❌ No residual risks listed

---

## Negative Test Cases

| ID | Test | Expected |
|----|------|----------|
| ZF001 | verdict_pass_without_zero_finding_justification | FAIL |
| ZF002 | zero_finding_missing_timeout_review | FAIL |
| ZF003 | three_pass_phases_without_justification_pending | PENDING |
| ZF009 | zero_finding_without_evidence_anchor_fails | FAIL |

---

## Related Documents

- `docs/VERIFIER_MANDATE.md` - Verifier Mandate Contract 设计
- `docs/PLAN_COVERAGE_GATE.md` - Plan Coverage Gate 设计
- `docs/ANOMALY_LEDGER.md` - Historical Anomaly Ledger 设计
