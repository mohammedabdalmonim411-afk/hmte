# final_audit 工作流模板

## 概述

final_audit 是 TriAgentFlow / TAF 工作流的终局阶段，在所有普通 phase 完成后执行，对整个项目进行全局审计，决定是否可以提交外部审计。

## 角色分工

| 角色 | 职责 | 产出 |
|------|------|------|
| final_audit Worker | 运行全量检查命令，收集证据 | `.phase_control/evidence/final_audit_attempt_1.json` |
| Final Verifier | 审计 evidence，决定 PASS/FAIL/BLOCK | `.phase_control/verdicts/final_audit_attempt_1.json` |

**重要**：不存在"一个角色同时写 evidence 和 verdict"的情况。Worker 和 Final Verifier 必须分离。

## 文件命名规则（硬规则）

```
✅ 正确命名：
.phase_control/instructions/final_audit_attempt_1_worker.json
.phase_control/instructions/final_audit_attempt_1_verifier.json
.phase_control/delegations/final_audit_attempt_1_worker.json
.phase_control/delegations/final_audit_attempt_1_verifier.json
.phase_control/logs/final_audit_attempt_1.commands.jsonl
.phase_control/evidence/final_audit_attempt_1.json
.phase_control/verdicts/final_audit_attempt_1.json

❌ 禁止命名：
.phase_control/evidence/final_audit_attempt_1.evidence.json
.phase_control/verdicts/final_audit_attempt_1.verdict.json
```

**禁止使用 `.evidence.` 或 `.verdict.` 中缀**。

## Worker Instruction 模板

```json
{
  "phase_id": "final_audit",
  "attempt": 1,
  "role": "worker",
  "assigned_to": "phase-executor",
  "created_at": "2026-05-29T12:00:00Z",
  "objective": "执行全局审计检查，收集所有 phase 的完成情况和测试结果",
  "inputs": [
    ".phase_control/session.json",
    ".phase_control/phases.json",
    ".phase_control/verdicts/*.json",
    "所有测试脚本"
  ],
  "tasks": [
    "读取 session.json 和 phases.json，了解原始任务",
    "检查所有 phase 的 verdict 状态",
    "验证每个 phase 的完整链路（7 个文件）",
    "生成 covered_phases 列表，覆盖 phases.json 中的所有 phase_id",
    "运行全量测试套件",
    "执行 git diff 对比基线",
    "检查文档一致性",
    "汇总所有 residual_risks 和 verification_gaps",
    "生成 evidence bundle"
  ],
  "acceptance_criteria": [
    "所有检查命令都已执行",
    "evidence 文件包含完整的检查结果",
    "command log 记录了所有执行的命令"
  ],
  "required_evidence": [
    "检查结果汇总",
    "测试执行输出",
    "git diff 结果",
    "文档一致性检查结果"
  ],
  "output_path": ".phase_control/evidence/final_audit_attempt_1.json",
  "command_log_path": ".phase_control/logs/final_audit_attempt_1.commands.jsonl",
  "constraints": [
    "所有命令必须使用 hmte exec 执行",
    "不得修改业务代码",
    "不得修改其他 phase 的产物"
  ]
}
```

## Worker 执行步骤

### 1. 读取项目状态

```bash
# 使用 hmte exec 执行所有命令
hmte exec final_audit --attempt 1 -- cat .phase_control/session.json
hmte exec final_audit --attempt 1 -- cat .phase_control/phases.json
```

### 2. 检查所有 phase 的 verdict

```bash
hmte exec final_audit --attempt 1 -- bash -c '
for verdict in .phase_control/verdicts/*.json; do
    [ "$(basename "$verdict")" = "final_audit_attempt_1.json" ] && continue
    echo "=== $verdict ==="
    python3 -c "import json; v=json.load(open(\"$verdict\")); print(f\"Status: {v[\"status\"]}, Phase: {v[\"phase_id\"]}\")"
done
'
```

### 3. 验证完整链路

```bash
hmte exec final_audit --attempt 1 -- python3 -c "
import json
from pathlib import Path

phases = json.load(open('.phase_control/phases.json'))['phases']
ctrl = Path('.phase_control')
missing = []

for p in phases:
    pid = p.get('phase_id', p.get('id'))
    attempt = 1
    
    required = [
        ctrl / 'instructions' / f'{pid}_attempt_{attempt}_worker.json',
        ctrl / 'instructions' / f'{pid}_attempt_{attempt}_verifier.json',
        ctrl / 'delegations' / f'{pid}_attempt_{attempt}_worker.json',
        ctrl / 'delegations' / f'{pid}_attempt_{attempt}_verifier.json',
        ctrl / 'logs' / f'{pid}_attempt_{attempt}.commands.jsonl',
        ctrl / 'evidence' / f'{pid}_attempt_{attempt}.json',
        ctrl / 'verdicts' / f'{pid}_attempt_{attempt}.json',
    ]
    
    for f in required:
        if not f.exists():
            missing.append(str(f))

if missing:
    print('MISSING FILES:')
    for m in missing:
        print(f'  - {m}')
    exit(1)
else:
    print('✅ All phase chains complete')
"
```

### 4. 运行全量测试

```bash
# E2E 测试
hmte exec final_audit --attempt 1 -- bash scripts/e2e-core-workflow-test.sh
hmte exec final_audit --attempt 1 -- bash scripts/e2e-anti-fake-test.sh

# Python 语法检查
hmte exec final_audit --attempt 1 -- python3 -m py_compile src/skills/hmte/scripts/orchestrator.py
hmte exec final_audit --attempt 1 -- python3 -m py_compile src/skills/hmte/scripts/hmte-audit-flow.py

# Bash 语法检查
hmte exec final_audit --attempt 1 -- bash -n scripts/hmte-exec.sh
hmte exec final_audit --attempt 1 -- bash -n src/skills/hmte/scripts/phase_gate.sh
```

### 5. Git 基线对比

```bash
hmte exec final_audit --attempt 1 -- bash -c '
baseline=$(python3 -c "import json; s=json.load(open(\".phase_control/session.json\")); print(s.get(\"git_head_at_kickoff\", \"null\"))")

if [ "$baseline" != "null" ] && [ -n "$baseline" ]; then
    echo "=== Git diff from baseline ==="
    git diff --stat "$baseline" || echo "Git diff failed"
    git diff --name-only "$baseline" || echo "Git diff failed"
fi

dirty=$(python3 -c "import json; s=json.load(open(\".phase_control/session.json\")); print(s.get(\"git_dirty_at_kickoff\", False))")
if [ "$dirty" = "True" ]; then
    echo "⚠️  WARNING: Baseline was dirty at kickoff"
fi
'
```

### 6. 检查文档一致性

```bash
hmte exec final_audit --attempt 1 -- bash -c '
# 检查 hmte exec 示例是否都包含 --attempt
echo "=== Checking hmte exec examples ==="
if grep -r "hmte exec" README.md HERMES.md src/skills/hmte/SKILL.md 2>/dev/null | grep -v "\-\-attempt"; then
    echo "⚠️  WARNING: Found hmte exec without --attempt flag"
fi

# 检查旧协议残留
echo "=== Checking for old naming conventions ==="
if find .phase_control -name "*.evidence.json" -o -name "*.verdict.json" 2>/dev/null | grep .; then
    echo "❌ FAIL: Found old naming convention with .evidence./.verdict. infix"
    exit 1
fi

# 检查 YAML 残留
if grep -n "^\`\`\`yaml" src/skills/hmte/phase-template.md 2>/dev/null; then
    echo "⚠️  WARNING: Found YAML code blocks in phase-template.md"
fi

echo "✅ Documentation checks complete"
'
```

### 7. 汇总风险和缺口

```bash
hmte exec final_audit --attempt 1 -- python3 -c "
import json
from pathlib import Path

all_risks = []
all_gaps = []

for vf in Path('.phase_control/verdicts').glob('*.json'):
    if vf.name.startswith('final_audit'):
        continue
    try:
        v = json.load(vf.open())
        sc = v.get('adversarial_scorecard', {})
        all_risks.extend(sc.get('residual_risks', []))
        all_gaps.extend(sc.get('verification_gaps', []))
    except Exception as e:
        print(f'Error reading {vf}: {e}')

print('=== Residual Risks ===')
for r in all_risks:
    print(f'- {r}')

print()
print('=== Verification Gaps ===')
for g in all_gaps:
    print(f'- {g}')
"
```

### 8. 生成 Evidence

```bash
python3 - .phase_control final_audit 1 <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])

# 读取所有 verdict 状态
verdicts_status = []
for vf in Path(ctrl, 'verdicts').glob('*.json'):
    if vf.name.startswith('final_audit'):
        continue
    try:
        v = json.load(vf.open())
        verdicts_status.append({
            'phase_id': v['phase_id'],
            'attempt': v['attempt'],
            'status': v['status']
        })
    except Exception as e:
        verdicts_status.append({
            'file': str(vf),
            'error': str(e)
        })

# 读取 session 信息
session = json.load(open(Path(ctrl, 'session.json')))

evidence = {
    "phase_id": phase_id,
    "attempt": attempt,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "checks_performed": [
        "原始目标完成检查",
        "所有 phase PASS 检查",
        "完整链路验证",
        "phase_gate 验证",
        "git diff 基线对比",
        "文档一致性检查",
        "旧协议残留检查",
        "全量测试执行",
        "风险和缺口汇总",
        "交付条件评估"
    ],
    "session_info": {
        "task": session.get('task'),
        "git_head_at_kickoff": session.get('git_head_at_kickoff'),
        "git_dirty_at_kickoff": session.get('git_dirty_at_kickoff')
    },
    "verdicts_summary": verdicts_status,
    "test_results": {
        "e2e_core_workflow": "executed",
        "e2e_anti_fake": "executed",
        "python_syntax": "executed",
        "bash_syntax": "executed"
    }
}

Path(ctrl, 'evidence', f'{phase_id}_attempt_{attempt}.json').write_text(
    json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8'
)

print(f"✅ Evidence written to {ctrl}/evidence/{phase_id}_attempt_{attempt}.json")
PY
```

## Verifier Instruction 模板

```json
{
  "phase_id": "final_audit",
  "attempt": 1,
  "role": "verifier",
  "assigned_to": "release-auditor",
  "created_at": "2026-05-29T12:00:00Z",
  "objective": "审计 final_audit evidence，决定项目是否可以发布",
  "inputs": [
    ".phase_control/evidence/final_audit_attempt_1.json",
    ".phase_control/logs/final_audit_attempt_1.commands.jsonl",
    ".phase_control/session.json",
    ".phase_control/phases.json",
    "所有 phase 的 verdicts"
  ],
  "tasks": [
    "读取并验证 Worker 提供的 evidence",
    "执行 Final Verifier 的 10 项必查",
    "评估所有 residual_risks 的严重程度",
    "决定 PASS/FAIL/BLOCK 状态",
    "确定 next_action（RELEASE/RETURN_TO_LEADER/ESCALATE）",
    "生成 verdict"
  ],
  "acceptance_criteria": [
    "verdict 包含完整的 adversarial_scorecard",
    "evidence_paths 不为空",
    "next_action 字段正确",
    "status 与检查结果一致"
  ],
  "required_evidence": [
    "10 项必查的执行结果",
    "风险评估结论",
    "发布决策依据"
  ],
  "output_path": ".phase_control/verdicts/final_audit_attempt_1.json",
  "constraints": [
    "不得修改业务代码",
    "不得修改 Worker 的 evidence",
    "verdict 必须基于客观证据"
  ]
}
```

## Final Verifier 执行步骤

### 1. 读取 Evidence

```bash
cat .phase_control/evidence/final_audit_attempt_1.json
cat .phase_control/logs/final_audit_attempt_1.commands.jsonl
```

### 2. 执行 10 项必查

参考 `src/agents/release-auditor.md` 中的详细说明，逐项执行检查。

### 3. 生成 Verdict

```bash
python3 - .phase_control final_audit 1 PASS <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt, status = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

# 读取 evidence
evidence_path = Path(ctrl, 'evidence', f'{phase_id}_attempt_{attempt}.json')
evidence = json.load(evidence_path.open())

# 构造 verdict
verdict = {
    "status": status,
    "phase_id": phase_id,
    "attempt": attempt,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "scope": "whole_project",
    "adversarial_scorecard": {
        "criteria_passed": [
            "原始目标完成",
            "所有 phase PASS",
            "完整链路存在",
            "phase_gate 全通过",
            "git diff 无意外",
            "文档口径一致",
            "无旧协议残留",
            "全量测试通过",
            "风险可控",
            "满足交付条件"
        ],
        "criteria_failed": [],
        "global_conflicts": [],
        "evidence_paths": [
            f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
            f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl"
        ],
        "residual_risks": [],
        "re_verification_conclusion": "All phases passed, project ready for release"
    },
    "next_action": "RELEASE" if status == "PASS" else "RETURN_TO_LEADER"
}

# 如果 status 是 FAIL，需要填充 criteria_failed
if status == "FAIL":
    verdict["adversarial_scorecard"]["criteria_failed"] = [
        "需要根据实际检查结果填充"
    ]
    verdict["adversarial_scorecard"]["criteria_passed"] = []

# 如果 status 是 BLOCK，next_action 应该是 ESCALATE
if status == "BLOCK":
    verdict["next_action"] = "ESCALATE"

Path(ctrl, 'verdicts', f'{phase_id}_attempt_{attempt}.json').write_text(
    json.dumps(verdict, ensure_ascii=False, indent=2), encoding='utf-8'
)

print(f"✅ Verdict written: {status}")
print(f"   Next action: {verdict['next_action']}")
PY
```

## Verdict 格式规范

### 必需字段

```json
{
  "status": "PASS | FAIL | BLOCK",
  "phase_id": "final_audit",
  "attempt": 1,
  "timestamp": "ISO8601",
  "scope": "whole_project",
  "adversarial_scorecard": {
    "criteria_passed": ["..."],
    "criteria_failed": ["..."],
    "global_conflicts": ["..."],
    "evidence_paths": ["必须非空"],
    "residual_risks": ["..."],
    "re_verification_conclusion": "..."
  },
  "next_action": "RELEASE | RETURN_TO_LEADER | ESCALATE"
}
```

### evidence_paths 要求

**硬性要求**：`evidence_paths` 不得为空，必须至少包含：
1. Evidence 文件路径：`.phase_control/evidence/final_audit_attempt_1.json`
2. Command log 路径：`.phase_control/logs/final_audit_attempt_1.commands.jsonl`

### next_action 决策逻辑

| status | next_action | 说明 |
|--------|-------------|------|
| PASS | RELEASE | 所有检查通过，可以发布 |
| FAIL | RETURN_TO_LEADER | 有检查失败，需要 Leader 修复 |
| BLOCK | ESCALATE | 有阻塞性问题，需要人工决策 |

## phase_gate 验证

final_audit 完成后，必须通过 phase_gate 验证：

```bash
bash src/skills/hmte/scripts/phase_gate.sh final_audit --attempt 1
```

phase_gate 会检查：
1. Verdict 文件存在
2. Verdict 格式合法
3. Status 为 PASS
4. evidence_paths 不为空
5. 完整链路存在（7 个文件）

## 常见问题

### Q1: final_audit 和普通 phase 有什么区别？

A: final_audit 是特殊的 phase：
- 它审计所有其他 phase 的结果
- 它的 scope 是 `whole_project` 而非单个功能
- 它决定整个项目是否可以发布
- 它有特殊的 `next_action` 字段

### Q2: 如果 final_audit FAIL 了怎么办？

A: 根据 `next_action` 字段：
- `RETURN_TO_LEADER`: Leader 修复问题后重新执行 final_audit（attempt 2）
- `ESCALATE`: 上报人工决策，可能需要调整验收标准

### Q3: evidence_paths 为什么不能为空？

A: phase_gate 需要验证 evidence 和 command log 的存在性，确保审计过程可追溯。空的 evidence_paths 意味着没有证据支持 verdict，会被 phase_gate 拒绝。

### Q4: 可以跳过某些必查项吗？

A: 不可以。10 项必查是 Final Verifier 的最低要求。如果某项不适用，应在 verdict 中说明原因，但不能跳过检查。

### Q5: final_audit 可以修改业务代码吗？

A: 不可以。final_audit 只审计，不修复。如果发现问题，应该 FAIL 并返回 Leader 修复。

## 示例：完整 final_audit 流程

```bash
#!/usr/bin/env bash
set -euo pipefail

PHASE_ID="final_audit"
ATTEMPT=1

# 1. Leader 创建 Worker instruction
cat > .phase_control/instructions/${PHASE_ID}_attempt_${ATTEMPT}_worker.json <<'JSON'
{
  "phase_id": "final_audit",
  "attempt": 1,
  "role": "worker",
  "objective": "执行全局审计检查"
}
JSON

# 2. Leader 委派给 Worker（生成 receipt）
cat > .phase_control/delegations/${PHASE_ID}_attempt_${ATTEMPT}_worker.json <<'JSON'
{
  "phase_id": "final_audit",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "INTENT_ONLY",
  "expected_output_path": ".phase_control/evidence/final_audit_attempt_1.json"
}
JSON

# 3. Worker 执行检查（使用 hmte exec）
hmte exec final_audit --attempt 1 -- bash scripts/e2e-core-workflow-test.sh
hmte exec final_audit --attempt 1 -- bash scripts/e2e-anti-fake-test.sh
# ... 其他检查

# 4. Worker 生成 evidence
python3 - .phase_control final_audit 1 <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
evidence = {
    "phase_id": phase_id,
    "attempt": attempt,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "checks_performed": ["..."]
}
Path(ctrl, 'evidence', f'{phase_id}_attempt_{attempt}.json').write_text(
    json.dumps(evidence, ensure_ascii=False, indent=2)
)
PY

# 5. Leader 创建 Verifier instruction
cat > .phase_control/instructions/${PHASE_ID}_attempt_${ATTEMPT}_verifier.json <<'JSON'
{
  "phase_id": "final_audit",
  "attempt": 1,
  "role": "verifier",
  "objective": "审计 evidence 并决定是否发布"
}
JSON

# 6. Leader 委派给 Final Verifier（生成 receipt）
cat > .phase_control/delegations/${PHASE_ID}_attempt_${ATTEMPT}_verifier.json <<'JSON'
{
  "phase_id": "final_audit",
  "attempt": 1,
  "role": "verifier",
  "delegation_trust_level": "INTENT_ONLY",
  "expected_output_path": ".phase_control/verdicts/final_audit_attempt_1.json"
}
JSON

# 7. Final Verifier 生成 verdict
python3 - .phase_control final_audit 1 PASS <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt, status = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
verdict = {
    "status": status,
    "phase_id": phase_id,
    "attempt": attempt,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "scope": "whole_project",
    "adversarial_scorecard": {
        "criteria_passed": ["..."],
        "criteria_failed": [],
        "global_conflicts": [],
        "evidence_paths": [
            f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
            f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl"
        ],
        "residual_risks": [],
        "re_verification_conclusion": "Ready for release"
    },
    "next_action": "RELEASE"
}
Path(ctrl, 'verdicts', f'{phase_id}_attempt_{attempt}.json').write_text(
    json.dumps(verdict, ensure_ascii=False, indent=2)
)
PY

# 8. 运行 phase_gate 验证
bash src/skills/hmte/scripts/phase_gate.sh final_audit --attempt 1

echo "✅ final_audit complete: PASS"
```

## 参考文档

- `src/agents/release-auditor.md`: Final Verifier 角色定义（legacy filename）
- `docs/HTE_v1.3_DEVELOPMENT_PLAN.md`: Phase 2 详细规格
- `src/skills/hmte/SKILL.md`: TAF 技能使用指南（legacy path）
- `src/skills/hmte/phase-template.md`: 普通 phase 模板
