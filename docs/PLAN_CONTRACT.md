# Plan Contract

**Version**: 1.0  
**Status**: Draft  
**Last Updated**: 2026-06-10

---

## 1. Purpose

Plan Contract 标准化项目计划书，让所有 P0/P1/P2、验收标准、必跑测试、不做项都有可追踪 ID。

Worker instruction / Verifier instruction / evidence / verdict / gate 都能引用 plan item。

---

## 2. Plan Contract Format

Plan Contract 必须包含以下字段：

### 2.1 Metadata

```markdown
# Plan Contract

**Plan ID**: {project}-PLAN-{version}-{date}
**Version**: {semantic_version}
**Project**: {project_name}
**Status**: draft | locked | amended
```

### 2.2 Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | ... | P0 | ... |
| S-002 | ... | P1 | ... |
| ... | ... | ... | ... |

**ID 格式**: `S-{number}`，3 位数字，零填充。

### 2.3 Non-Scope

| ID | Item | Reason |
|----|------|--------|
| NS-001 | ... | ... |
| NS-002 | ... | ... |
| ... | ... | ... |

**ID 格式**: `NS-{number}`，3 位数字，零填充。

### 2.4 Phases

| ID | Phase | Goal | Plan Items |
|----|-------|------|------------|
| P-001 | Phase 1 | ... | S-001, S-002 |
| P-002 | Phase 2 | ... | S-003 |
| ... | ... | ... | ... |

**ID 格式**: `P-{number}`，3 位数字，零填充。

### 2.5 Acceptance Criteria

| ID | Criterion | Related Plan Item | Verification Method |
|----|-----------|-------------------|---------------------|
| AC-001 | ... | S-001 | code_review |
| AC-002 | ... | S-002 | automated_test |
| ... | ... | ... | ... |

**ID 格式**: `AC-{number}`，3 位数字，零填充。

**Verification Method**: 
- `code_review`
- `automated_test`
- `manual_test`
- `integration_test`
- `documentation_review`

### 2.6 Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | ... | P0-1 | negative |
| T-002 | ... | P0-2 | positive |
| ... | ... | ... | ... |

**ID 格式**: `T-{number}`，3 位数字，零填充。

**Type**: `positive` | `negative`

### 2.7 Required Negative Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| NT-001 | ... | P0-1 | negative |
| NT-002 | ... | P0-3 | negative |
| ... | ... | ... | ... |

**ID 格式**: `NT-{number}`，3 位数字，零填充。

### 2.8 Allowed Files

| ID | Path | Reason |
|----|------|--------|
| A-001 | docs/ | 文档目录 |
| A-002 | scripts/ | 脚本目录 |
| ... | ... | ... |

**ID 格式**: `A-{number}`，3 位数字，零填充。

### 2.9 Forbidden Files

| ID | Path | Reason |
|----|------|--------|
| F-001 | .phase_control/ | 不提交 Git |
| F-002 | dogfood_regression/ | 不提交 Git |
| ... | ... | ... |

**ID 格式**: `F-{number}`，3 位数字，零填充。

### 2.10 Risk Register

| ID | Risk | Level | Mitigation |
|----|------|-------|------------|
| R-001 | ... | P0 | ... |
| R-002 | ... | P1 | ... |
| ... | ... | ... | ... |

**ID 格式**: `R-{number}`，3 位数字，零填充。

**Level**: `P0` | `P1` | `P2`

### 2.11 Dogfood Requirements

| ID | Requirement | Verification |
|----|-------------|--------------|
| D-001 | v2.0 用 v2.0 封版 | release_gate PASS |
| D-002 | planted lazy-path cases | 项目内 gate/eval 捕获 |
| ... | ... | ... |

**ID 格式**: `D-{number}`，3 位数字，零填充。

### 2.12 Release Conditions

| ID | Condition | Verification |
|----|-----------|--------------|
| RC-001 | P0 = 0 | release_gate |
| RC-002 | P1 = 0 | release_gate |
| ... | ... | ... |

**ID 格式**: `RC-{number}`，3 位数字，零填充。

### 2.13 Stop Conditions

| ID | Condition | Action |
|----|-----------|--------|
| SC-001 | 违反五条宪法 | BLOCK |
| SC-002 | P0 > 0 且无法修复 | BLOCK |
| ... | ... | ... |

**ID 格式**: `SC-{number}`，3 位数字，零填充。

**Action**: `BLOCK` | `FAIL` | `PENDING`

---

## 3. Plan Item Granularity Rule

每个 plan item 必须：

- 有唯一 ID
- 有明确 required_steps
- 有 verification_method
- 有 required_tests 或 required_artifacts
- 能被 Worker 派发
- 能被 Verifier 审计
- 能被 gate 检查

**禁止大而空表述作为唯一验收语义**，例如：

- 实现所有核心功能
- 完成相关优化
- 基本达成
- 适当处理
- 视情况验证
- 后续完善

如果 plan item 过宽，plan contract validation 必须 FAIL。

---

## 4. Canonical Plan Contract（唯一机器可读真理源）

**真理源层级**：

1. Markdown 计划书是人读文件，保留为原始输入
2. Gate 使用的 truth source 必须是 **canonical plan contract**（从计划书生成的结构化 JSON/YAML）
3. `plan_hash` 应锁定 canonical contract，而不是自由 Markdown 排版
4. `phases.json` 不能成为真理源，只能是 locked plan 的派生
5. coverage / fidelity 的基线必须来自 locked plan，不得来自 Leader 后续生成的缩水版 phases.json
6. Git commit hash 可作为 optional baseline，不作为强依赖

---

## 5. Canonical Plan Contract Schema

```json
{
  "plan_id": "string",
  "version": "string",
  "project": "string",
  "status": "draft | locked | amended",
  "scope": [
    {
      "id": "S-001",
      "item": "string",
      "priority": "P0 | P1 | P2",
      "description": "string"
    }
  ],
  "non_scope": [
    {
      "id": "NS-001",
      "item": "string",
      "reason": "string"
    }
  ],
  "phases": [
    {
      "id": "P-001",
      "phase": "Phase 1",
      "goal": "string",
      "plan_items": ["S-001", "S-002"]
    }
  ],
  "acceptance_criteria": [
    {
      "id": "AC-001",
      "criterion": "string",
      "related_plan_item": "S-001",
      "verification_method": "code_review | automated_test | manual_test | integration_test | documentation_review"
    }
  ],
  "required_tests": [
    {
      "id": "T-001",
      "test": "string",
      "phase": "P0-1",
      "type": "positive | negative"
    }
  ],
  "required_negative_tests": [
    {
      "id": "NT-001",
      "test": "string",
      "phase": "P0-1",
      "type": "negative"
    }
  ],
  "allowed_files": [
    {
      "id": "A-001",
      "path": "string",
      "reason": "string"
    }
  ],
  "forbidden_files": [
    {
      "id": "F-001",
      "path": "string",
      "reason": "string"
    }
  ],
  "risk_register": [
    {
      "id": "R-001",
      "risk": "string",
      "level": "P0 | P1 | P2",
      "mitigation": "string"
    }
  ],
  "dogfood_requirements": [
    {
      "id": "D-001",
      "requirement": "string",
      "verification": "string"
    }
  ],
  "release_conditions": [
    {
      "id": "RC-001",
      "condition": "string",
      "verification": "string"
    }
  ],
  "stop_conditions": [
    {
      "id": "SC-001",
      "condition": "string",
      "action": "BLOCK | FAIL | PENDING"
    }
  ]
}
```

---

## 6. Plan Contract Validation Rules

Plan Contract 验证脚本必须检查：

1. **ID 唯一性**: 所有 ID 在同一类别内唯一
2. **ID 格式**: 符合 `{category}-{number}` 格式
3. **必需字段**: 所有必需字段存在
4. **引用完整性**: 所有 plan item 引用存在
5. **粒度检查**: plan item 不能过宽
6. **禁止短语**: 不包含大而空表述
7. **验证方法**: verification_method 必须是允许值之一
8. **优先级**: priority 必须是 P0/P1/P2 之一
9. **状态**: status 必须是 draft/locked/amended 之一
10. **相互引用**: acceptance_criteria 引用的 plan item 必须存在

---

## 7. Example Plan Contract

```markdown
# Plan Contract

**Plan ID**: TAF-PLAN-v2.0-20260608
**Version**: 1.0
**Project**: TriAgentFlow / TAF v2.0
**Status**: draft

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Plan Contract | P0 | 标准化项目计划书 |
| S-002 | Plan Lock | P0 | 计划书锁定机制 |

## Non-Scope

| ID | Item | Reason |
|----|------|--------|
| NS-001 | 新增核心 Agent | 违反三 Agent 宪法 |
| NS-002 | DAG / 拓扑排序 | 过度工程 |

## Phases

| ID | Phase | Goal | Plan Items |
|----|-------|------|------------|
| P-001 | Phase 1 | Plan Contract | S-001 |
| P-002 | Phase 2 | Plan Lock | S-002 |

## Acceptance Criteria

| ID | Criterion | Related Plan Item | Verification Method |
|----|-----------|-------------------|---------------------|
| AC-001 | Plan Contract 包含可追踪 ID | S-001 | code_review |
| AC-002 | Plan Lock 阻止未 lock 执行 | S-002 | automated_test |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | PC003_plan_item_without_id_fails | P0-1 | negative |
| T-002 | PD001_worker_instruction_missing_plan_ref | P0-3 | negative |

## Required Negative Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| NT-001 | PC003_plan_item_without_id_fails | P0-1 | negative |
| NT-002 | PD001_worker_instruction_missing_plan_ref | P0-3 | negative |

## Allowed Files

| ID | Path | Reason |
|----|------|--------|
| A-001 | docs/ | 文档目录 |
| A-002 | scripts/ | 脚本目录 |

## Forbidden Files

| ID | Path | Reason |
|----|------|--------|
| F-001 | .phase_control/ | 不提交 Git |
| F-002 | dogfood_regression/ | 不提交 Git |

## Risk Register

| ID | Risk | Level | Mitigation |
|----|------|-------|------------|
| R-001 | Leader 阉割计划书 | P0 | Plan-to-Delegation Fidelity |
| R-002 | Verifier 礼貌型 PASS | P0 | Verifier Mandate Contract |

## Dogfood Requirements

| ID | Requirement | Verification |
|----|-------------|--------------|
| D-001 | v2.0 用 v2.0 封版 | release_gate PASS |
| D-002 | planted lazy-path cases | 项目内 gate/eval 捕获 |

## Release Conditions

| ID | Condition | Verification |
|----|-----------|--------------|
| RC-001 | P0 = 0 | release_gate |
| RC-002 | P1 = 0 | release_gate |

## Stop Conditions

| ID | Condition | Action |
|----|-----------|--------|
| SC-001 | 违反五条宪法 | BLOCK |
| SC-002 | P0 > 0 且无法修复 | BLOCK |
```

---

## 8. Usage

### 8.1 Validate Plan Contract

```bash
# 验证 Plan Contract 格式
bash scripts/hmte-plan-contract.sh --plan HTE_v2.0_PROJECT_PLAN.md

# 生成 canonical JSON
bash scripts/hmte-plan-contract.sh --plan HTE_v2.0_PROJECT_PLAN.md --generate-canonical

# 验证 canonical JSON
bash scripts/hmte-plan-contract.sh --canonical plan_contract.json --validate
```

### 8.2 Reference Plan Item

Worker instruction:

```json
{
  "plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids": ["S-001", "S-002", "AC-001"]
  }
}
```

Verifier instruction:

```json
{
  "audit_plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids_to_audit": ["S-001", "S-002", "AC-001"]
  }
}
```

---

## 9. Troubleshooting

### Q1: Plan item 过宽怎么办？

拆分成多个粒度更小的 plan item，每个都有明确的 required_steps 和 verification_method。

### Q2: ID 冲突怎么办？

修改 ID 编号，确保同一类别内唯一。

### Q3: canonical JSON 与 Markdown 不一致怎么办？

重新生成 canonical JSON，或手动修复 Markdown。

### Q4: plan_hash 如何生成？

```bash
bash scripts/hmte-plan-contract.sh --plan HTE_v2.0_PROJECT_PLAN.md --generate-canonical
# 输出 canonical JSON
sha256sum plan_contract.json
```

---

## 10. See Also

- [Plan Lock](PLAN_LOCK.md)
- [Plan-to-Delegation Fidelity](PLAN_TO_DELEGATION_FIDELITY.md)
- [Verifier Mandate Contract](VERIFIER_MANDATE.md)
- [Plan Coverage Gate](PLAN_COVERAGE_GATE.md)
