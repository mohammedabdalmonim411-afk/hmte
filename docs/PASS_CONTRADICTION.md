# PASS Contradiction Detector

**Version**: 1.0  
**Status**: Stable  
**Part of**: TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance  

---

## Purpose

防止 **最终报告洗白历史异常**。

如果历史中存在异常但 final report 写全部通过，release_gate 必须 FAIL。

---

## Principles

1. **Final Report Must Be Structured** — 不能只写"44/44 PASS"，必须有结构化字段
2. **Field-Level Comparison** — release_gate 对比 final report 与 anomaly ledger / test disposition 的字段级数据
3. **Contradiction is Failure** — 矛盾即失败，不是可以调和的差异
4. **No Keywords-Only Detection** — 不依赖关键词检测，使用结构化 schema

---

## Final Report Schema

Final report 必须包含结构化字段，不能只写自然语言总结。

```json
{
  "report_id": "FINAL-REPORT-v2.0-20260608",
  "plan_id": "TAF-PLAN-v2.0-20260608",
  "tests_total": 26,
  "tests_passed": 23,
  "tests_failed": 3,
  "tests_skipped": 0,
  "tests_timed_out": 0,
  "open_anomalies": 1,
  "accepted_risks": 0,
  "closed_anomalies": 0,
  "unresolved_required_tests": [],
  "unresolved_required_artifacts": [],
  "downgraded_p1_items": [],
  "phase_summary": [
    {
      "phase_id": "phase_7",
      "verdict": "PASS",
      "tests_passed": 23,
      "tests_failed": 3,
      "anomalies": ["ANM-001"]
    }
  ],
  "conclusion": "PASS with 1 open anomaly (ANM-001: partial test pass)"
}
```

---

## Contradiction Detection Rules

### Rule 1: Tests Count Mismatch

```
IF 历史中存在：
  - partial test pass (23/26)
  - test timeout
  - skipped test

AND final report 的 tests_passed == tests_total 且没有结构化解释差异：
  → release_gate FAIL
```

### Rule 2: Anomaly Mismatch

```
IF anomaly_ledger.entries.filter(status == "open").length > 0

AND final_report.open_anomalies == 0：
  → release_gate FAIL
```

### Rule 3: Required Tests Mismatch

```
IF test_disposition.entries.filter(status == "unresolved").length > 0

AND final_report.unresolved_required_tests == []：
  → release_gate FAIL
```

### Rule 4: Natural Language Washing

```
IF final report 只有自然语言总结（如 "all checks passed"）

AND 缺少结构化字段（tests_total, tests_passed, tests_failed）：
  → release_gate FAIL
```

---

## Contradiction Report Schema

```json
{
  "contradiction_detected": true,
  "contradictions": [
    {
      "contradiction_id": "CON-001",
      "type": "partial_pass_vs_full_pass",
      "history": {
        "phase_id": "phase_7",
        "anomaly": "23/26 tests passed",
        "status": "unresolved"
      },
      "final_report": {
        "claim": "44/44 PASS",
        "explanation": null
      },
      "severity": "P0"
    }
  ],
  "recommendation": "BLOCK release until contradiction is resolved"
}
```

---

## Usage

### Check Contradiction

```bash
# 检查 final report 与历史 anomaly 一致性
bash scripts/hmte-pass-contradiction.sh \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --anomaly-ledger .phase_control/anomaly_ledger.json \
  --final-report .phase_control/final_report.json
```

---

## Integration with release_gate

release_gate 必须检查：

1. ✅ final report 有结构化字段
2. ✅ `tests_total` / `tests_passed` / `tests_failed` / `tests_skipped` / `tests_timed_out` 与历史一致
3. ✅ `open_anomalies` 与 anomaly ledger 一致
4. ✅ `unresolved_required_tests` 与 test disposition 一致
5. ✅ 如果有矛盾，release_gate FAIL

---

## Negative Test Cases

| ID | Test | Expected |
|----|------|----------|
| PCON001 | final_pass_conflicts_with_phase_partial_pass | FAIL |
| PCON002 | production_ready_with_unresolved_anomaly | FAIL |
| PCON003 | 44_44_pass_hides_23_26_history | FAIL |
| PCON004 | release_pack_missing_failure_context | FAIL |
| PCON005 | final_summary_washes_failed_history | FAIL |
| PCON009 | final_report_structured_pass_conflicts_with_anomaly_ledger | FAIL |

---

## Related Documents

- `docs/ANOMALY_LEDGER.md` - Historical Anomaly Ledger 设计
- `docs/TEST_DISPOSITION_GATE.md` - Test Disposition Gate 设计
- `docs/ZERO_FINDING.md` - Zero-Finding Justification 设计
