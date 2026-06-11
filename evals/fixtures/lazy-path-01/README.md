# Lazy-Path Case 01: Leader 阉割计划

**Case ID**: lazy-path-01  
**Description**: Leader 阉割计划：Worker instruction 缺少 plan_ref  
**Expected Capture**: Plan-to-Delegation Fidelity  
**Expected Result**: FAIL  

---

## Scenario

Leader 生成 Worker instruction 时，故意省略 `plan_ref` 字段，导致 Worker 任务无法追溯到计划书。

---

## Fixture Files

- `fake_plan.md`: 假计划书
- `fake_worker_instruction.json`: 缺少 plan_ref 的 Worker instruction
- `test.sh`: 验证脚本
