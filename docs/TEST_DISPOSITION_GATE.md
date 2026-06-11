# Test Disposition Gate

**Version**: 1.0  
**Status**: Stable  
**Part of**: TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance  
**Priority**: P0-7

---

## Purpose

确保所有 failed/skipped/timeout 测试都有明确的处置记录，防止通过跳过慢测试或用核心测试替代完整验收测试来绕过验证要求。

Test Disposition Gate 是审计链的关键环节，确保测试失败不会被静默忽略，测试跳过必须有计划授权。

---

## Principles

1. **No Silent Failure** — 任何 failed/skipped/timeout test 必须有处置记录
2. **No Performance Shortcuts** — 禁止以"测试太慢"为由跳过测试
3. **No Core-for-Full Substitution** — 禁止用核心测试替代完整验收测试
4. **Plan Authorization Required** — 测试跳过必须有 plan 明确授权
5. **Verifier Must Approve** — 替代证据必须经过 Verifier 批准
6. **Complete Set Check** — 必须执行差集检查：`required_tests - actual_tests`

---

## Test Disposition Schema

Test disposition 记录保存到：`.phase_control/test_dispositions/{phase_id}_attempt_{n}.json`

```json
{
  "phase_id": "implement_auth",
  "attempt": 1,
  "disposition_records": [
    {
      "test_name": "tests/auth.test.js::test_login_invalid_credentials",
      "expected_by_plan": true,
      "actual_result": "failed",
      "skipped_or_failed_reason": "Database connection timeout in test environment",
      "plan_authorized": false,
      "replacement_evidence": {
        "type": "manual_verification",
        "description": "Manually verified with curl against staging environment",
        "evidence_path": ".phase_control/manual_evidence/auth_login_test.txt"
      },
      "verifier_decision": "APPROVED",
      "verifier_reasoning": "Replacement evidence sufficient; test environment DB config issue tracked in INFRA-123",
      "status": "DISPOSED"
    },
    {
      "test_name": "tests/auth.test.js::test_login_performance",
      "expected_by_plan": false,
      "actual_result": "skipped",
      "skipped_or_failed_reason": "Performance test not in plan required_tests",
      "plan_authorized": false,
      "replacement_evidence": null,
      "verifier_decision": "NOT_REQUIRED",
      "verifier_reasoning": "Not in locked plan required_tests",
      "status": "WAIVED"
    }
  ],
  "missing_required_tests": [],
  "disposition_complete": true,
  "generated_at": "2026-06-09T10:30:00Z"
}
```

---

## Disposition Record Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `test_name` | string | ✅ | 测试完整标识符（路径::函数名） |
| `expected_by_plan` | boolean | ✅ | 是否在 locked_plan.required_tests 中 |
| `actual_result` | enum | ✅ | `"passed"` \| `"failed"` \| `"skipped"` \| `"timeout"` |
| `skipped_or_failed_reason` | string | ✅ (if not passed) | 失败/跳过原因，必须具体，不得笼统 |
| `plan_authorized` | boolean | ✅ | 跳过是否有计划授权 |
| `replacement_evidence` | object \| null | ✅ | 替代证据（如果有） |
| `verifier_decision` | enum | ✅ | `"APPROVED"` \| `"REJECTED"` \| `"NOT_REQUIRED"` |
| `verifier_reasoning` | string | ✅ | Verifier 决策理由（≥50 字符） |
| `status` | enum | ✅ | `"DISPOSED"` \| `"WAIVED"` \| `"BLOCKED"` |

---

## Replacement Evidence Schema

如果测试失败/跳过但需要提供替代证据，必须包含：

```json
{
  "type": "manual_verification" | "alternative_test" | "integration_test" | "production_evidence",
  "description": "详细说明替代证据的性质和覆盖范围",
  "evidence_path": ".phase_control/manual_evidence/...",
  "coverage_comparison": "说明替代证据相比原测试的覆盖差异",
  "risk_assessment": "说明接受替代证据的风险"
}
```

---

## Forbidden Reasons

以下原因 **不得** 作为跳过测试的理由，Verifier 必须 REJECT：

| Forbidden Reason | Why Forbidden | Correct Action |
|------------------|---------------|----------------|
| "测试太慢" | Performance 不是跳过测试的理由 | 优化测试或接受慢速度 |
| "测试不稳定" | Flaky test 必须修复，不能跳过 | 修复测试或提供稳定替代证据 |
| "核心测试已覆盖" | 核心测试不能替代完整验收测试 | 执行完整测试 |
| "时间不够" | 时间压力不是降低质量的理由 | 调整计划或延长时间 |
| "环境问题" | 环境问题必须解决或提供等效证据 | 修复环境或提供替代证据 |

---

## Diff Set Check

Test Disposition Gate 必须执行差集检查：

```python
# Pseudo-code
locked_plan_tests = load_locked_plan().required_tests  # Set of test names
evidence_tests = load_evidence().tests_run | tests_failed | tests_skipped | tests_timed_out

missing_required_tests = locked_plan_tests - evidence_tests

if missing_required_tests:
    # FAIL: Required tests not attempted
    verdict = "FAIL"
    reason = f"Missing {len(missing_required_tests)} required tests: {missing_required_tests}"
```

**Critical**: 如果 `missing_required_tests` 非空，Gate 必须 FAIL，即使所有已执行测试都通过。

---

## Gate Check Logic

```python
def check_test_disposition_gate(phase_id, attempt):
    evidence = load_evidence(phase_id, attempt)
    disposition = load_disposition(phase_id, attempt)
    locked_plan = load_locked_plan()
    
    # 1. Diff set check
    missing_tests = locked_plan.required_tests - evidence.all_tests
    if missing_tests:
        return FAIL("Missing required tests", missing_tests)
    
    # 2. Check failed/skipped/timeout tests have disposition
    problematic_tests = evidence.failed | evidence.skipped | evidence.timeout
    for test in problematic_tests:
        if test not in disposition.records:
            return FAIL(f"Test {test} has no disposition record")
        
        record = disposition.records[test]
        
        # 3. Check forbidden reasons
        if is_forbidden_reason(record.reason):
            return FAIL(f"Forbidden skip reason for {test}: {record.reason}")
        
        # 4. Check plan authorization
        if record.expected_by_plan and not record.plan_authorized:
            if not record.replacement_evidence:
                return FAIL(f"Required test {test} skipped without replacement")
            
            if record.verifier_decision != "APPROVED":
                return FAIL(f"Replacement evidence not approved for {test}")
    
    # 5. Check disposition complete
    if not disposition.disposition_complete:
        return FAIL("Disposition incomplete")
    
    return PASS()
```

---

## Integration with phase_gate

phase_gate 必须调用 Test Disposition Gate：

```bash
# phase_gate checks
1. Evidence bundle exists ✅
2. Verdict exists ✅
3. Plan lock valid ✅
4. Test disposition valid ✅ (NEW)
5. Timeline valid ✅
```

如果 Test Disposition Gate FAIL，phase_gate 必须 FAIL。

---

## Integration with Verifier

Verifier 在生成 verdict 时必须：

1. ✅ 检查所有 failed/skipped/timeout 测试
2. ✅ 对每个测试生成 disposition record
3. ✅ 对替代证据做独立评估
4. ✅ 拒绝所有 forbidden reasons
5. ✅ 检查 diff set: `required_tests - actual_tests`
6. ✅ 在 verdict 中引用 disposition file path

Verifier 必须在 adversarial mindset 下评估：
- 替代证据是否真正等效？
- 跳过理由是否合理？
- 是否存在用简单测试替代复杂测试的企图？

---

## Audit Trail

Test Disposition Gate 生成审计记录：

**路径**: `.phase_control/audit_trail/test_disposition_{phase_id}_attempt_{n}.log`

```
[2026-06-09T10:30:00Z] Test Disposition Gate START
[2026-06-09T10:30:01Z] Loaded locked_plan: 15 required tests
[2026-06-09T10:30:01Z] Loaded evidence: 14 tests run, 1 skipped
[2026-06-09T10:30:01Z] Diff check: 0 missing required tests
[2026-06-09T10:30:02Z] Disposition check: 1 record found
[2026-06-09T10:30:02Z] Verifier decision: APPROVED for test_login_invalid_credentials
[2026-06-09T10:30:02Z] Test Disposition Gate PASS
```

---

## Hard Rules

1. ✅ 任何 failed/skipped/timeout test 没有 disposition record → FAIL
2. ✅ Forbidden reason 出现 → FAIL
3. ✅ Required test 跳过且无 plan authorization 且无 verifier-approved replacement → FAIL
4. ✅ `missing_required_tests` 非空 → FAIL
5. ✅ Verifier decision 不是 APPROVED 但测试仍算 pass → FAIL
6. ✅ Replacement evidence 没有 coverage_comparison 和 risk_assessment → FAIL

---

## Anti-Patterns

### ❌ Anti-Pattern 1: Performance Excuse
```json
{
  "reason": "测试需要 5 分钟，太慢了",
  "verifier_decision": "APPROVED"
}
```
**Why Wrong**: Performance 不是跳过测试的理由。

**Correct**:
```json
{
  "reason": "测试需要 5 分钟，已优化但仍需 3 分钟，接受慢速度",
  "replacement_evidence": null,
  "verifier_decision": "NOT_REQUIRED"
}
```

### ❌ Anti-Pattern 2: Core-for-Full Substitution
```json
{
  "reason": "核心测试已经覆盖了主要场景",
  "replacement_evidence": {
    "type": "alternative_test",
    "description": "用核心测试替代完整验收测试"
  }
}
```
**Why Wrong**: 核心测试不能替代完整验收测试。

**Correct**: 执行完整验收测试，或提供等效的 integration test 作为替代。

### ❌ Anti-Pattern 3: Vague Reason
```json
{
  "reason": "环境问题",
  "verifier_decision": "APPROVED"
}
```
**Why Wrong**: 理由太笼统。

**Correct**:
```json
{
  "reason": "Test database connection timeout due to INFRA-123 (network policy blocking port 5432). Replacement: manual curl test against staging DB.",
  "replacement_evidence": { ... }
}
```

---

## Usage

### Generate Disposition Record (Verifier)

```bash
# Verifier 生成 disposition record
bash scripts/hmte-test-disposition.sh \
  --phase implement_auth \
  --attempt 1 \
  --generate
```

### Verify Disposition (phase_gate)

```bash
# phase_gate 验证 disposition
bash scripts/hmte-test-disposition.sh \
  --phase implement_auth \
  --attempt 1 \
  --verify
```

### Check Diff Set

```bash
# 检查 missing required tests
bash scripts/hmte-test-disposition.sh \
  --phase implement_auth \
  --attempt 1 \
  --check-diff
```

---

## Related Documents

- `docs/PLAN_LOCK.md` - Plan Lock 设计，required_tests 来源
- `docs/HTE_PROTOCOL.md` - Evidence Bundle 和 Verdict 格式
- `docs/RELEASE_GATE_PROTOCOL.md` - Release Gate 集成
- `docs/VERIFIER_MANDATE.md` - Verifier 职责和 adversarial mindset

---

## FAQ

### Q: 如果测试环境真的有问题怎么办？

A: 提供等效的替代证据，如 manual verification 或 integration test。但必须说明：
- 具体是什么环境问题（不能笼统说"环境问题"）
- 替代证据如何等效
- 接受替代证据的风险

### Q: 如果测试真的太慢怎么办？

A: 优化测试。如果优化后仍然慢，接受慢速度。Performance 不是跳过测试的理由。

### Q: 如果核心测试已经覆盖了怎么办？

A: 核心测试不能替代完整验收测试。如果 plan 要求完整验收测试，必须执行。如果认为核心测试足够，需要通过 plan amendment 修改 required_tests。

### Q: 如果时间不够怎么办？

A: 调整计划或延长时间。时间压力不是降低质量的理由。

### Q: Verifier 必须为每个 failed test 都 REJECT 吗？

A: 不是。Verifier 可以 APPROVE 有合理替代证据的 failed test。但必须独立评估替代证据是否等效。

---

## Version History

- **v1.0** (2026-06-09): Initial version for TriAgentFlow / TAF v2.0 Plan-Grounded Audit Governance
