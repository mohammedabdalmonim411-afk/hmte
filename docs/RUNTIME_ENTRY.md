# TriAgentFlow / TAF Runtime Entry Points

**Version**: 1.8.0  
**Purpose**: 明确 TriAgentFlow / TAF 运行入口、主路径与辅助路径、manual delegation fallback

---

## Primary Path (Canonical)

**Leader → Worker → Verifier → phase_gate**

这是 TriAgentFlow / TAF 的主路径，基于文件协议，不依赖任何运行时工具。

### Workflow
1. Leader 创建 `.phase_control/phases.json`
2. Leader 写入 `.phase_control/instructions/{phase_id}_attempt_{n}_worker.json`
3. Leader 通过 `delegate_task` 启动 Worker
4. Worker 执行任务，通过 `hmte exec` 运行命令
5. Worker 产出 evidence bundle
6. Leader 写入 `.phase_control/instructions/{phase_id}_attempt_{n}_verifier.json`
7. Leader 通过 `delegate_task` 启动 Verifier
8. Verifier 审计 evidence，产出 verdict
9. Leader 运行 `phase_gate.sh` 检查是否放行
10. 如 PASS，Leader 继续下一阶段；如 FAIL/BLOCK，打回或修复

**Note**: Instruction files are `.json` (canonical, required by gate/final-check). `.md` files can be used as optional companion notes alongside `.json`, but do not replace them.

**这是 TriAgentFlow / TAF 的核心，任何时候都可用。**

---

## Auxiliary Path (Optional)

**`hmte run` / orchestrator.py**

这是辅助入口，自动化 Leader 的部分工作（读取 phases.json，循环启动 Worker/Verifier）。

### When to Use
- phases.json 已经写好
- Leader 希望自动化循环执行
- orchestrator.py 可用（skill 已安装或项目本地存在）

### When NOT to Use
- orchestrator.py 不可用
- phases.json schema 不兼容
- 需要更灵活的控制流
- 项目环境复杂（路径问题、依赖问题）

**orchestrator 不可用时，可以切换到 manual delegation（主路径）。**

---

## Manual Delegation Fallback

如果 orchestrator 不可用，Leader 可以切换到 manual delegation：

### Requirements
1. ✅ 允许切换（不是协议违反）
2. ✅ 必须在 `docs/planning/DECISION_LOG.md` 或 `.phase_control/DECISION_LOG.md` 中记录切换原因
3. ✅ 不得跳过 receipt / command log / evidence / verdict / phase_gate
4. ✅ 不得修改验收标准
5. ✅ 不得新增角色
6. ✅ 仍需产出完整证据链

### Example Decision Log Entry
```markdown
## D001: Switch to Manual Delegation

**Date**: 2026-06-03  
**Context**: orchestrator.py not found in skill path, schema incompatible  
**Decision**: Use manual Leader→Worker→Verifier delegation  
**Reason**: orchestrator is auxiliary, not required; manual path is canonical  
**Impact**: Leader manually manages phase transitions, still follows file protocol
```

---

## Path Discovery Order

### HMTE_SKILL_DIR Resolution

```bash
# Priority order:
1. $HMTE_SKILL_DIR (environment variable)
2. $PROJECT_ROOT/src/skills/hmte/ (project-local)
3. ~/.hermes/skills/hmte/ (user Hermes skill)
4. /usr/local/share/hermes/skills/hmte/ (global install)
```

### orchestrator.py Location

```bash
# Priority order:
1. $HMTE_SKILL_DIR/scripts/orchestrator.py
2. $PROJECT_ROOT/src/skills/hmte/scripts/orchestrator.py
3. ~/.hermes/skills/hmte/scripts/orchestrator.py
4. /usr/local/share/hermes/skills/hmte/scripts/orchestrator.py
```

If not found in any location → fallback to manual delegation.

---

## Key Principles

1. **File protocol is primary** — orchestrator is optional automation
2. **Manual delegation is always valid** — not a workaround
3. **Orchestrator is helper** — not a new core Agent
4. **Fallback is legitimate** — document in DECISION_LOG
5. **No runtime required** — TAF is files + scripts

---

## Minimal Manual Delegation Walkthrough

This 1-phase example shows the complete manual path (80 lines max).

### Step 1: Create Worker Instruction
```bash
cat > .phase_control/instructions/phase_a_attempt_1_worker.json <<EOF
{
  "phase_id": "phase_a",
  "attempt": 1,
  "role": "worker",
  "goal": "Implement feature X",
  "acceptance_criteria": ["Tests pass", "Code linted"]
}
EOF
```

### Step 2: Create Worker Receipt
```bash
cat > .phase_control/delegations/phase_a_attempt_1_worker.json <<EOF
{
  "phase_id": "phase_a",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "delegated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

### Step 3: Run Commands via hmte exec
```bash
bash scripts/hmte-exec.sh phase_a --attempt 1 -- npm test
bash scripts/hmte-exec.sh phase_a --attempt 1 -- npm run lint
```

### Step 4: Write Evidence
```bash
cat > .phase_control/evidence/phase_a_attempt_1.json <<EOF
{
  "phase_id": "phase_a",
  "attempt": 1,
  "status": "completed",
  "worker_name": "manual-worker",
  "goal_summary": "Implement feature X",
  "planned_output": "Working implementation + tests",
  "changed_files": ["src/feature.js", "tests/feature.test.js"],
  "commands_run": ["npm test", "npm run lint"],
  "command_exit_codes": [0, 0],
  "command_log_path": ".phase_control/logs/phase_a_attempt_1.commands.jsonl",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

### Step 5: Create Verifier Instruction
```bash
cat > .phase_control/instructions/phase_a_attempt_1_verifier.json <<EOF
{
  "phase_id": "phase_a",
  "attempt": 1,
  "role": "verifier",
  "evidence_path": ".phase_control/evidence/phase_a_attempt_1.json"
}
EOF
```

### Step 6: Create Verifier Receipt
```bash
cat > .phase_control/delegations/phase_a_attempt_1_verifier.json <<EOF
{
  "phase_id": "phase_a",
  "attempt": 1,
  "role": "verifier",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "delegated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

### Step 7: Write Verdict (Verifier)
```bash
cat > .phase_control/verdicts/phase_a_attempt_1.json <<EOF
{
  "status": "PASS",
  "phase_id": "phase_a",
  "attempt": 1,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "adversarial_scorecard": {
    "criteria_passed": [
      {
        "criterion": "Tests pass",
        "evidence": ".phase_control/logs/phase_a_attempt_1.commands.jsonl: npm test exit_code=0"
      },
      {
        "criterion": "Code linted",
        "evidence": ".phase_control/logs/phase_a_attempt_1.commands.jsonl: npm run lint exit_code=0"
      }
    ],
    "criteria_failed": [],
    "evidence_paths": [
      ".phase_control/evidence/phase_a_attempt_1.json",
      ".phase_control/logs/phase_a_attempt_1.commands.jsonl"
    ],
    "verification_method": "cross_check",
    "risk_disposition": [
      {
        "risk": "none",
        "disposition": "accepted",
        "reason": "All acceptance criteria met with evidence"
      }
    ],
    "residual_risks": ["none"],
    "re_verification_conclusion": "Evidence bundle and command log verified. All acceptance criteria have supporting evidence.",
    "independently_verified_files": ["src/feature.js", "tests/feature.test.js"],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  }
}
EOF
```

### Step 8: Run phase_gate
```bash
# 优先使用项目本地脚本（如已复制）
bash scripts/phase_gate.sh phase_a --attempt 1

# 或使用 TAF legacy hmte skill 路径
export HMTE_SKILL_DIR=~/.hermes/skills/hmte
bash "$HMTE_SKILL_DIR/scripts/phase_gate.sh" phase_a --attempt 1
```

If PASS (exit 0), proceed to next phase. If FAIL (exit 1), fix and retry.

---

**Document Version**: 1.8.0  
**Last Updated**: 2026-06-04  
**Status**: Authoritative
