# Plan Coverage Gate

**Version**: 2.0  
**Status**: Active  
**Last Updated**: 2026-06-10  

---

## 1. Purpose

Plan Coverage Gate 确保 evidence 和 verdict 覆盖了计划书要求的所有 plan items。防止 Worker 只做容易部分、Leader 阉割计划、Verifier 礼貌型 PASS。

---

## 2. Design Principles

1. **Plan is Truth** — 人审计划书是原始真理，所有执行和审计必须引用 plan
2. **Coverage is Mandatory** — evidence 必须覆盖 plan_ref items，verdict 必须覆盖 audit_plan_ref items
3. **Required Tests Must Execute** — required tests 缺失必须 FAIL
4. **Non-Scope Must Not Implement** — non_scope 被实现必须 FAIL
5. **PASS Must Explain Coverage** — PASS verdict 必须解释 plan coverage

---

## 3. Coverage Checks

### 3.1 Evidence Plan Coverage

**检查项**：

1. `evidence.plan_ref` 存在且非空
2. `evidence.plan_ref.plan_hash` 与 locked plan hash 一致
3. `evidence.plan_ref.plan_item_ids` 非空
4. `evidence.plan_ref.plan_item_ids` 覆盖该 phase 的所有 required plan items
5. `evidence.evidence_by_plan_item` 包含所有 plan_item_ids 的证据锚点

**失败条件**：

- `plan_ref` 缺失 → FAIL
- `plan_hash` 不一致 → FAIL
- `plan_item_ids` 为空 → FAIL
- `plan_item_ids` 少于 plan 要求 → FAIL
- `evidence_by_plan_item` 缺失 → FAIL

### 3.2 Verdict Plan Coverage

**检查项**：

1. `verdict.audit_plan_ref` 存在且非空
2. `verdict.audit_plan_ref.plan_hash` 与 locked plan hash 一致
3. `verdict.audit_plan_ref.plan_item_ids_to_audit` 非空
4. `verdict.plan_item_ids_checked` 非空
5. `verdict.plan_item_ids_checked` 覆盖该 phase 的所有 required plan items

**失败条件**：

- `audit_plan_ref` 缺失 → FAIL
- `plan_hash` 不一致 → FAIL
- `plan_item_ids_to_audit` 为空 → FAIL
- `plan_item_ids_checked` 为空 → FAIL
- `plan_item_ids_checked` 少于 plan 要求 → FAIL

### 3.3 Required Tests Coverage

**检查项**：

1. 从 locked plan 提取该 phase 的 `required_tests`
2. 检查 `evidence.tests_run` 是否包含所有 `required_tests`
3. 检查 `evidence.tests_failed` / `tests_skipped` / `tests_timed_out` 中是否有 required tests

**失败条件**：

- `required_tests` 中有测试未在 `tests_run` / `tests_failed` / `tests_skipped` / `tests_timed_out` 中 → FAIL
- `required_tests` 在 `tests_failed` 中且无 disposition → FAIL（由 Test Disposition Gate 处理）

### 3.4 Required Negative Tests Coverage

**检查项**：

1. 从 locked plan 提取该 phase 的 `required_negative_tests`
2. 检查 `evidence.tests_run` 是否包含所有 `required_negative_tests`

**失败条件**：

- `required_negative_tests` 中有测试未在 `tests_run` 中 → FAIL

### 3.5 Non-Scope Violation Check

**检查项**：

1. 从 locked plan 提取 `non_scope` items
2. 检查 `evidence.changed_files` 是否包含 `non_scope` 中的 forbidden paths
3. 检查 `evidence.artifact_paths` 是否包含 `non_scope` 中的 forbidden paths

**失败条件**：

- `changed_files` 中包含 `non_scope` forbidden paths → FAIL
- `artifact_paths` 中包含 `non_scope` forbidden paths → FAIL

### 3.6 PASS Verdict Coverage Explanation

**检查项**：

1. PASS verdict 必须包含 `zero_finding_justification`（如果没有发现问题）
2. PASS verdict 必须包含 `plan_coverage_explanation`（解释如何覆盖 plan items）

**失败条件**：

- PASS verdict 无 `zero_finding_justification` 且无 `plan_coverage_explanation` → FAIL

---

## 4. Integration with phase_gate.sh

### 4.1 检查顺序

phase_gate.sh 按以下顺序执行检查：

1. Audit Flow Check（现有）
2. **Plan-to-Delegation Fidelity Check**（Phase 3，新增）
3. **Verifier Mandate Contract Check**（Phase 4，新增）
4. **Plan Coverage Gate Check**（Phase 5，新增）
5. Verdict Status Check（现有）
6. Verifier Minimum Audit Check（现有）

### 4.2 调用方式

```bash
# Plan Coverage Gate Check
bash scripts/phase_gate.sh \
  --phase-id phase_5 \
  --check-plan-coverage \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-lock .phase_control/plan_lock.json
```

### 4.3 失败行为

- 任何检查失败 → phase_gate FAIL
- 所有检查通过 → phase_gate PASS

---

## 5. Pre-Integration Hooks

为 Phase 6-9 预留 fail-closed hooks：

### 5.1 Anomaly Ledger Hook（Phase 6）

```bash
# Anomaly Ledger check (Phase 6, pre-integration mode)
if [[ -f "scripts/hmte-anomaly-ledger.sh" ]]; then
  bash scripts/hmte-anomaly-ledger.sh --evidence "$EVIDENCE_FILE" || ((errors++))
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
  echo "ERROR: hmte-anomaly-ledger.sh not found (required in $GATE_MODE mode)"
  ((errors++))
else
  echo "SKIP: hmte-anomaly-ledger.sh not implemented yet (pre-integration mode)"
fi
```

### 5.2 Test Disposition Hook（Phase 7）

```bash
# Test Disposition check (Phase 7, pre-integration mode)
if [[ -f "scripts/hmte-test-disposition.sh" ]]; then
  bash scripts/hmte-test-disposition.sh --evidence "$EVIDENCE_FILE" --plan "$PLAN_FILE" || ((errors++))
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
  echo "ERROR: hmte-test-disposition.sh not found (required in $GATE_MODE mode)"
  ((errors++))
else
  echo "SKIP: hmte-test-disposition.sh not implemented yet (pre-integration mode)"
fi
```

### 5.3 PASS Contradiction Hook（Phase 8）

```bash
# PASS Contradiction check (Phase 8, pre-integration mode)
if [[ -f "scripts/hmte-pass-contradiction.sh" ]]; then
  bash scripts/hmte-pass-contradiction.sh --plan "$PLAN_FILE" --anomaly-ledger "$ANOMALY_LEDGER" || ((errors++))
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
  echo "ERROR: hmte-pass-contradiction.sh not found (required in $GATE_MODE mode)"
  ((errors++))
else
  echo "SKIP: hmte-pass-contradiction.sh not implemented yet (pre-integration mode)"
fi
```

### 5.4 Zero-Finding Hook（Phase 9）

```bash
# Zero-Finding check (Phase 9, pre-integration mode)
if [[ -f "scripts/hmte-check-mandate.sh" ]]; then
  bash scripts/hmte-check-mandate.sh --verdict "$VERDICT_FILE" --check-zero-finding || ((errors++))
elif [[ "$GATE_MODE" == "release" || "$GATE_MODE" == "dogfood" ]]; then
  echo "ERROR: hmte-check-mandate.sh --check-zero-finding not found (required in $GATE_MODE mode)"
  ((errors++))
else
  echo "SKIP: zero-finding check not implemented yet (pre-integration mode)"
fi
```

### 5.5 Hook 规则

1. **pre-integration mode**（Phase 5-9 开发期间）：hook 脚本不存在时 SKIP
2. **release / dogfood mode**（Phase 10+ 完成后）：hook 脚本不存在时 FAIL（fail-closed）
3. **standard mode**：hook 脚本不存在时 SKIP

---

## 6. Coverage Report Format

```json
{
  "plan_coverage": {
    "plan_id": "TAF-PLAN-v2.0-20260608",
    "plan_hash": "sha256:abc123...",
    "phase_id": "phase_5",
    "plan_items_required": ["S-001", "S-002", "AC-001"],
    "plan_items_covered_by_evidence": ["S-001", "S-002", "AC-001"],
    "plan_items_missing_from_evidence": [],
    "coverage_rate": 1.0,
    "required_tests_executed": ["T-001"],
    "required_tests_missing": [],
    "negative_tests_executed": ["NT-001"],
    "negative_tests_missing": [],
    "non_scope_violations": [],
    "verdict_plan_coverage_explained": true
  }
}
```

---

## 7. Examples

### 7.1 PASS: Full Coverage

```json
{
  "evidence": {
    "plan_ref": {
      "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
      "plan_hash": "sha256:abc123",
      "plan_item_ids": ["S-001", "S-002", "AC-001"]
    },
    "evidence_by_plan_item": {
      "S-001": {
        "changed_files": ["docs/PLAN_CONTRACT.md"],
        "tests": ["T-001"],
        "verifier_checked": true
      },
      "S-002": {
        "changed_files": ["scripts/hmte-plan-contract.sh"],
        "tests": ["T-001"],
        "verifier_checked": true
      },
      "AC-001": {
        "tests": ["T-001"],
        "verifier_checked": true
      }
    },
    "tests_run": ["T-001"],
    "tests_failed": [],
    "tests_skipped": [],
    "tests_timed_out": []
  },
  "verdict": {
    "audit_plan_ref": {
      "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
      "plan_hash": "sha256:abc123",
      "plan_item_ids_to_audit": ["S-001", "S-002", "AC-001"]
    },
    "plan_item_ids_checked": ["S-001", "S-002", "AC-001"],
    "zero_finding_justification": {
      "checked_plan_items": ["S-001", "S-002", "AC-001"],
      "checked_files": ["docs/PLAN_CONTRACT.md", "scripts/hmte-plan-contract.sh"],
      "why_no_p0": "All P0 plan items covered by evidence"
    }
  }
}
```

### 7.2 FAIL: Missing Plan Item

```json
{
  "evidence": {
    "plan_ref": {
      "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
      "plan_hash": "sha256:abc123",
      "plan_item_ids": ["S-001"]
    }
  }
}
```

**Result**: FAIL — plan_item_ids 少于 plan 要求（缺少 S-002、AC-001）

### 7.3 FAIL: Required Test Missing

```json
{
  "evidence": {
    "plan_ref": {
      "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
      "plan_hash": "sha256:abc123",
      "plan_item_ids": ["S-001", "S-002", "AC-001"]
    },
    "tests_run": [],
    "tests_failed": [],
    "tests_skipped": [],
    "tests_timed_out": []
  }
}
```

**Result**: FAIL — required_tests 中的测试未在 tests_run 中

### 7.4 FAIL: Non-Scope Violation

```json
{
  "evidence": {
    "plan_ref": {
      "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
      "plan_hash": "sha256:abc123",
      "plan_item_ids": ["S-001", "S-002", "AC-001"]
    },
    "changed_files": ["scripts/hmte-anomaly-ledger.sh"]
  }
}
```

**Result**: FAIL — `scripts/hmte-anomaly-ledger.sh` 在 Phase 5 non_scope 中（Phase 6 才允许）

---

## 8. Verification

### 8.1 Acceptance Criteria

1. ✅ evidence 缺少 plan_ref 时，phase_gate 必须 FAIL
2. ✅ evidence 的 plan_item_ids 少于 plan 要求时，phase_gate 必须 FAIL
3. ✅ required tests 缺失时，phase_gate 必须 FAIL
4. ✅ required negative tests 缺失时，phase_gate 必须 FAIL
5. ✅ non_scope 被实现时，phase_gate 必须 FAIL
6. ✅ PASS verdict 未解释 plan coverage 时，phase_gate 必须 FAIL

### 8.2 Test Cases

| ID | Test | Type | Expected |
|----|------|------|----------|
| PC004 | required_tests_missing_from_plan_fails | negative | FAIL |
| PC005 | evidence_missing_plan_ref_fails | negative | FAIL |
| PC006 | evidence_plan_item_ids_incomplete_fails | negative | FAIL |
| PC007 | non_scope_violation_fails | negative | FAIL |

---

## 9. Related Documents

- [Plan Contract](PLAN_CONTRACT.md)
- [Plan Lock](PLAN_LOCK.md)
- [Plan-to-Delegation Fidelity](PLAN_TO_DELEGATION_FIDELITY.md)
- [Verifier Mandate Contract](VERIFIER_MANDATE.md)

---

**Document Hash**: [待生成]  
**Last Reviewed**: 2026-06-10  
