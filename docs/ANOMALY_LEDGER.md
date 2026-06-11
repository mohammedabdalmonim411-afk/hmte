# Historical Anomaly Ledger

**Version**: 1.0  
**Status**: Stable  
**Part of**: TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance  

---

## Purpose

记录全流程异常。**unresolved anomaly 不允许被最终 PASS 覆盖**。

Final verifier 必须逐项处置 anomaly，release_gate 必须检查 unresolved anomaly。

---

## Principles

1. **All Anomalies Must Be Recorded** — 所有异常必须记录到 ledger
2. **No Silent Failures** — 不允许忽略异常
3. **Unresolved Blocks Release** — unresolved P0/P1 anomaly 阻塞 release
4. **Disposition Required** — 每个 anomaly 必须有处置记录
5. **No Washing History** — final report 不能洗白历史异常

---

## Anomaly Types

| Type | Description | Default Severity |
|------|-------------|------------------|
| `worker_timeout` | Worker 执行超时 | P1 |
| `delegate_task_timeout` | delegate_task 调用超时 | P1 |
| `subagent_interrupted` | Subagent 被中断 | P1 |
| `test_timeout` | 测试超时 | P1 |
| `skipped_test` | 跳过测试 | P1 |
| `partial_test_pass` | 部分测试通过（如 23/26） | P1 |
| `coverage_report_missing` | 覆盖率报告缺失 | P1 |
| `integration_test_skipped` | 集成测试跳过 | P1 |
| `basic_achievement` | "基本达成" 描述 | P2 → P1* |
| `non_blocking` | "非阻断" 描述 | P2 → P1* |
| `future_optimization` | "后续优化" 描述 | P2 |
| `leader_local_takeover` | Leader 本地接管 Worker 任务 | P0 |
| `final_summary_conflict` | Final summary 与历史异常冲突 | P0 |

**注**：`*` 表示当与 required_tests / acceptance_criteria / required_artifacts 相关时，自动升级为 P1。

---

## Ledger Schema

```json
{
  "ledger_id": "ANOMALY-LEDGER-v2.0-20260608",
  "plan_id": "TAF-PLAN-v2.0-20260608",
  "entries": [
    {
      "entry_id": "ANM-001",
      "timestamp": "2026-06-08T12:00:00Z",
      "phase_id": "phase_7",
      "anomaly_type": "partial_test_pass",
      "description": "23/26 tests passed, 3 failed",
      "severity": "P1",
      "status": "open",
      "disposition": {
        "disposed_by": "verifier",
        "disposed_at": "2026-06-08T12:30:00Z",
        "reason": "3 failed tests are flaky, not related to core functionality",
        "replacement_evidence": ".phase_control/evidence/phase_7_attempt_2.json"
      },
      "related_plan_items": ["T-007", "AC-007"]
    }
  ]
}
```

---

## Status Values

| Status | Meaning |
|--------|---------|
| `open` | 未处置 |
| `closed` | 已修复，有 replacement_evidence |
| `accepted_risk` | 已接受风险（仅 P2 允许） |

---

## Ledger Rules

1. ✅ 所有异常必须记录到 ledger
2. ✅ unresolved anomaly 不允许被最终 PASS 覆盖
3. ✅ final verifier 必须逐项处置 anomaly
4. ✅ release_gate 必须检查 unresolved anomaly
5. ✅ 有 unresolved P1 anomaly 时，release_gate 必须 FAIL
6. ✅ 有 unresolved P0 anomaly 时，release_gate 必须 BLOCK

---

## Anomaly / accepted_risk 收紧

- ❌ P0 anomaly 绝不允许 accepted_risk
- ❌ P1 anomaly 不允许 Agent 自行 accepted_risk
- ✅ P1 anomaly 必须修复，或有证据降级为 P2
- ✅ P1 降级为 P2 必须有 evidence anchor，不能只写自然语言理由
- ✅ all accepted_risk 必须进入 final report 结构化清单
- ✅ release_gate 必须检查 accepted_risk，不得只看 open anomaly

---

## Independent Signal Source Rule

**phase_gate 必须从 command_log、test output summary、exit codes、duration、required_tests 反推 anomaly candidates**。

反推方法：
- command_log 中出现 `timeout` / `"timed out"` / `exit code != 0` → anomaly candidate
- test output summary 中出现 `skipped` / `"was not run"` / `"no tests ran"` → anomaly candidate
- test duration 异常（如 0s 或极短时间完成大量测试）→ anomaly candidate
- required_tests 中的测试未出现在 `tests_run` / `tests_failed` / `tests_skipped` / `tests_timed_out` 中 → anomaly candidate

如果 `derived_anomalies - ledger.entries != empty`，phase_gate FAIL。

---

## Usage

### Record Anomaly

```bash
# 记录异常
bash scripts/hmte-anomaly-ledger.sh \
  --record \
  --type "test_timeout" \
  --phase "phase_7" \
  --description "Integration test timed out after 300s" \
  --severity "P1"
```

### Check Anomalies

```bash
# 检查 unresolved anomaly
bash scripts/hmte-anomaly-ledger.sh \
  --check \
  --ledger .phase_control/anomaly_ledger.json
```

### Dispose Anomaly

```bash
# 处置异常
bash scripts/hmte-anomaly-ledger.sh \
  --dispose ANM-001 \
  --reason "Fixed in phase_7_attempt_2" \
  --replacement-evidence .phase_control/evidence/phase_7_attempt_2.json
```

---

## Integration with phase_gate

phase_gate 必须：
1. ✅ 检查 anomaly ledger 存在
2. ✅ 从 command_log / test output 反推 anomaly candidates
3. ✅ 对比 derived_anomalies 与 ledger.entries
4. ✅ 如果有未记录的异常，phase_gate FAIL

---

## Integration with release_gate

release_gate 必须：
1. ✅ 检查 unresolved P0/P1 anomaly
2. ✅ 检查 accepted_risk 是否合理
3. ✅ 检查 final report 与 anomaly ledger 一致性
4. ✅ 如果有 unresolved P1 anomaly，release_gate FAIL
5. ✅ 如果有 unresolved P0 anomaly，release_gate BLOCK

---

## Negative Test Cases

| ID | Test | Expected |
|----|------|----------|
| AN001 | timeout_not_recorded_blocks_gate | FAIL |
| AN002 | skipped_required_test_without_disposition_blocks_gate | FAIL |
| AN003 | partial_test_pass_without_disposition_blocks_gate | FAIL |
| AN004 | basic_achievement_without_required_evidence_blocks_gate | FAIL |
| AN009 | p0_anomaly_accepted_risk_blocks_release | FAIL |
| AN010 | required_test_basic_achievement_escalates_to_p1 | FAIL |

---

## Related Documents

- `docs/TEST_DISPOSITION_GATE.md` - Test Disposition Gate 设计
- `docs/PASS_CONTRADICTION.md` - PASS Contradiction Detector 设计
- `docs/PLAN_COVERAGE_GATE.md` - Plan Coverage Gate 设计
