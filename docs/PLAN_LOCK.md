# Plan Lock

**Version**: 1.0  
**Status**: Draft  
**Last Updated**: 2026-06-10

---

## 1. Purpose

Plan Lock 机制防止计划书在执行过程中被随意变更，确保所有执行和审计都基于同一版本计划书。

---

## 2. Plan Lock Format

```json
{
  "plan_id": "TAF-PLAN-v2.0-20260608",
  "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
  "plan_hash": "sha256:abc123...",
  "approved_by": "human-reviewer",
  "approved_at": "2026-06-08T00:00:00Z",
  "scope_version": "1.0",
  "amendment_policy": {
    "requires_approval": true,
    "min_reason_length": 100,
    "allowed_amenders": ["human"]
  },
  "locked_at": "2026-06-08T00:00:00Z"
}
```

---

## 3. Plan Lock Rules

1. **未 lock 不能执行**: 计划书未 lock，不允许正式执行
2. **变更需要 amendment**: 计划书变更必须有 amendment
3. **amendment 需要审批**: amendment 必须有 reason（≥100 字符）和 approver
4. **plan_hash 必须一致**: Leader 派发任务引用的 plan_hash 与 lock 不一致时，gate 必须 FAIL
5. **lock 文件位置**: `.phase_control/plan_lock.json`

---

## 4. Amendment Hard Rules

1. **human-only**: `allowed_amenders` 只能是 `["human"]` 或 `["user"]`；Leader / Worker / Verifier 永远不得作为 amender
2. **no downgrade**: amendment 不得降低 P0/P1 required_tests、acceptance_criteria、verification_method；不得将 P0 降级为 P1/P2，不得将 P1 降级为 P2
3. **new lock version chain**: amendment 批准后必须生成新 plan_lock，保留 old_hash → new_hash 版本链
4. **version chain**: 旧 lock 必须保留，不得覆盖；amendment 必须引用 original_hash 和 new_hash
5. **min_reason_length**: ≥100 字符，必须说明变更原因、影响范围、风险评估
6. **amendment 不得新增 P0 项而不提供对应 evidence 要求**
7. **amendment 记录**: 保存到 `.phase_control/amendments/`

---

## 5. Amendment Format

```json
{
  "amendment_id": "AMD-001",
  "plan_id": "TAF-PLAN-v2.0-20260608",
  "original_hash": "sha256:abc123...",
  "new_hash": "sha256:def456...",
  "reason": "增加 Evidence Replay 能力。原计划未包含此能力，但在 Phase 5 发现需要此能力以支持 audit traceability。影响范围：新增 P1-5 项，不影响 P0 能力。风险：增加实现复杂度，但不阻塞核心闭环。",
  "approved_by": "human-reviewer",
  "approved_at": "2026-06-09T00:00:00Z",
  "changes": [
    {"type": "add", "item_id": "S-015", "description": "Evidence Replay"}
  ]
}
```

---

## 6. Plan Hash Calculation

Plan hash 应锁定 canonical plan contract，而不是自由 Markdown 排版。

```bash
# 生成 canonical JSON
bash scripts/hmte-plan-contract.sh --plan HTE_v2.0_PROJECT_PLAN.md --generate-canonical

# 计算 plan_hash
sha256sum HTE_v2.0_PROJECT_PLAN_canonical.json | awk '{print "sha256:" $1}'
```

---

## 7. Plan Lock Workflow

### 7.1 Initial Lock

```bash
# 1. 验证 Plan Contract
bash scripts/hmte-plan-contract.sh --plan HTE_v2.0_PROJECT_PLAN.md

# 2. 生成 canonical JSON
bash scripts/hmte-plan-contract.sh --plan HTE_v2.0_PROJECT_PLAN.md --generate-canonical

# 3. 生成 Plan Lock
bash scripts/hmte-plan-lock.sh --plan HTE_v2.0_PROJECT_PLAN.md --approved-by "human-reviewer"

# 4. 验证 Plan Lock
bash scripts/hmte-plan-lock.sh --verify
```

### 7.2 Amendment

```bash
# 1. 修改计划书
vim HTE_v2.0_PROJECT_PLAN.md

# 2. 创建 amendment
bash scripts/hmte-plan-lock.sh --amend \
  --reason "增加 Evidence Replay 能力。原计划未包含此能力..." \
  --approved-by "human-reviewer"

# 3. 验证新 Plan Lock
bash scripts/hmte-plan-lock.sh --verify
```

---

## 8. Gate Integration

### 8.1 phase_gate 检查

```bash
# phase_gate 必须检查 plan_lock
bash scripts/phase_gate.sh --phase-id phase_1 --attempt 1 --check-plan-lock
```

检查项：
1. plan_lock.json 存在
2. plan_hash 与当前计划书一致
3. Worker instruction 引用的 plan_hash 与 lock 一致
4. Verifier instruction 引用的 plan_hash 与 lock 一致

### 8.2 release_gate 检查

```bash
# release_gate 必须检查 plan_lock
bash scripts/hmte-release-gate.sh --check-plan-lock
```

检查项：
1. plan_lock.json 存在
2. plan_hash 与当前计划书一致
3. 所有 amendment 有合理 reason（≥100 字符）
4. 所有 amendment 有 human approver

---

## 9. Example Plan Lock

```json
{
  "plan_id": "TAF-PLAN-v2.0-20260608",
  "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
  "plan_hash": "sha256:1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890",
  "approved_by": "human-reviewer",
  "approved_at": "2026-06-08T10:00:00Z",
  "scope_version": "1.0",
  "amendment_policy": {
    "requires_approval": true,
    "min_reason_length": 100,
    "allowed_amenders": ["human"]
  },
  "locked_at": "2026-06-08T10:00:00Z"
}
```

---

## 10. Troubleshooting

### Q1: plan_hash 不一致怎么办？

检查是否修改了计划书但未创建 amendment。如果是合法修改，创建 amendment；如果是意外修改，恢复计划书。

### Q2: amendment reason 不足 100 字符怎么办？

补充详细说明：变更原因、影响范围、风险评估。

### Q3: 如何查看 amendment 历史？

```bash
ls -la .phase_control/amendments/
cat .phase_control/amendments/AMD-001.json
```

### Q4: 如何恢复到之前的版本？

```bash
# 查看 amendment 链
cat .phase_control/amendments/AMD-001.json

# 恢复到 original_hash 对应的版本
git checkout <commit_hash> HTE_v2.0_PROJECT_PLAN.md

# 重新 lock
bash scripts/hmte-plan-lock.sh --plan HTE_v2.0_PROJECT_PLAN.md --approved-by "human-reviewer"
```

---

## 11. See Also

- [Plan Contract](PLAN_CONTRACT.md)
- [Plan-to-Delegation Fidelity](PLAN_TO_DELEGATION_FIDELITY.md)
- [Verifier Mandate Contract](VERIFIER_MANDATE.md)
- [Plan Coverage Gate](PLAN_COVERAGE_GATE.md)
