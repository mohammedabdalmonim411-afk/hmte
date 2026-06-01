# HTE v1.3 生命周期加固 — 开发计划

> 版本：v1.1 + r2 + r3 + r4 合并定稿
> 日期：2026-05-29
> 状态：待执行
> 基线：HTE v1.2（commit `aad9ae0`，已推送 GitHub）

---

## 1. 总体目标

v1.2 管的是：Worker 执行 → evidence → Verifier 审计 → verdict → phase_gate 放行。

v1.3 要增加的是：
- **启动层**：任务如何正确开始（kickoff → session → phases.json）
- **终局层**：任务如何正确结束（final_audit → 全局审计 → 发布决策）
- **基线清理**：v1.2 遗留的协议不一致、测试缺口、文档冲突
- **Schema 增强**：delegation receipt 字段预留

## 2. 版本边界

### v1.3 做
- Phase 0：v1.2 基线清理（8 项修复）
- Phase 1：kickoff / audit-start 启动层
- Phase 2：final_audit / Release Auditor 终局层
- Phase 3：delegation receipt schema 增强
- e2e-lifecycle-test.sh 新增

### v1.3 明确不做
- orchestrator.py 自动追加 final_audit（推迟 v1.4）
- Dashboard / Parallel phases / SQLite / CI/CD / Windows
- OBSERVED 真实集成（只做 schema 预留）
- 自动修复 final_audit 发现的问题
- 多 Auditor 投票

---

## 3. 四阶段路线图

```
Phase 0 (基线清理) → Phase 1 (启动层) → Phase 2 (终局层) → Phase 3 (Schema增强)
     ↓                    ↓                    ↓                    ↓
  E2E 全通过         kickoff/audit-start   final_audit         receipt v2
                                              ↓
                                    e2e-lifecycle-test.sh
```

每个 Phase 完成后必须提交：
- 修改文件清单
- evidence bundle
- verifier verdict（PASS/FAIL）
- 实际运行命令和输出
- 未解决风险

---

## 4. 全局约束

### 运行时目录列表（8 个，全局统一）

```bash
RUNTIME_SUBDIRS="instructions evidence verdicts logs delegations errors pids traces"
```

所有脚本（kickoff、archive、force、reset、E2E）必须引用同一列表，不得硬编码不同版本。

### E2E 隔离

e2e-lifecycle-test.sh 必须在 mktemp 临时项目中运行，不复制真实 `.git`。

### JSON 写入方式

所有 JSON 写入使用 `python3 - heredoc + argv`，不得使用 `python3 -c` 拼字符串。

---

## 5. Phase 0 — v1.2 Baseline Cleanup

### 目标
清除 v1.2 内部遗留的协议不一致、测试缺口和文档冲突。

### 逐项排查结果

| # | 问题 | 状态 | 文件 | 风险 | 修复 |
|---|------|------|------|------|------|
| 0-1 | 旧文件名残留 | ✅ 不存在 | — | — | 不需要 |
| 0-2 | make_cmd_log 未传 --attempt | ❌ | `e2e-core-workflow-test.sh:42` | 🟡 | ✅ 必修 |
| 0-3 | receipt expected_output_path 未区分 Worker/Verifier | ❌ | `e2e-core-workflow-test.sh:32` | 🟡 | ✅ 必修 |
| 0-4 | Verifier Write 权限矛盾 | ⚠️ | `verifier.md:12-13` | 🟢 | ✅ 必修 |
| 0-5 | worktree isolation 误导 | ⚠️ | `phase-executor.md:17,142` | 🟢 | ✅ 必修 |
| 0-6 | SKILL.md 省略 --attempt | ❌ | `SKILL.md:143-145` | 🟡 | ✅ 必修 |
| 0-7 | phase-template.md 用 YAML | ⚠️ | `phase-template.md:7-238` | 🟡 | ✅ 必修 |
| 0-8 | install 校验遗漏 | ⚠️ | `install-to-hermes.sh:146` | 🟡 | ✅ 必修 |
| 0-9 | yq degraded | ✅ 已移除 | — | — | 不需要 |
| 0-10 | 重复校验逻辑 | ❌ | `phase_gate.sh` vs `audit-flow.py` | 🟢 | 规划不修，v1.4 |

### 详细修复方案

**0-2: make_cmd_log 传 --attempt**
```bash
# 改前
bash scripts/hmte-exec.sh "$phase_id" -- $cmd
# 改后
bash scripts/hmte-exec.sh "$phase_id" --attempt "$attempt" -- $cmd
```
- 文件：`scripts/e2e-core-workflow-test.sh`
- 验收：`grep -n 'hmte-exec.sh' scripts/e2e-core-workflow-test.sh` 确认含 `--attempt`

**0-3: receipt expected_output_path 区分**
```bash
if [ "$role" = "worker" ]; then
    expected=".phase_control/evidence/${phase_id}_attempt_${attempt}.json"
elif [ "$role" = "verifier" ]; then
    expected=".phase_control/verdicts/${phase_id}_attempt_${attempt}.json"
fi
```
- 文件：`scripts/e2e-core-workflow-test.sh`, `scripts/hmte-write-receipt.sh`
- 验收：Worker receipt 的 expected_output_path 含 `evidence/`

**0-4: Verifier 权限说明**
在 `src/agents/verifier.md` 中添加权限说明段落：
- Hermes 环境：通过 `delegate_task(toolsets=["terminal","file"])` 获得权限
- verdict 通过 Bash/Python 写入，不依赖 Write 工具
- 文件：`src/agents/verifier.md`

**0-5: worktree 说明修正**
```markdown
### 2. 工作隔离（由宿主环境决定）
- Claude Code：可能启用 worktree 隔离
- Hermes：由 Leader 的 delegate_task 配置决定
- 正确性保证来自 evidence/verdict，不依赖 worktree
```
- 文件：`src/agents/phase-executor.md`

**0-6: SKILL.md 补 --attempt**
所有 hmte exec 示例改为显式 `--attempt`：
```bash
hmte exec phase_a --attempt 1 -- npm test
```
- 文件：`src/skills/hmte/SKILL.md`

**0-7: phase-template.md YAML → JSON**
所有 ````yaml` 代码块改为 ````json`。
- 文件：`src/skills/hmte/phase-template.md`
- 验收：`grep -n '\`\`\`yaml' src/skills/hmte/phase-template.md` 无输出

**0-8: install 校验补全**
```bash
# 改前
for script in write_state.py collect_evidence.sh phase_gate.sh; do
# 改后
for script in write_state.py collect_evidence.sh phase_gate.sh hmte-audit-flow.py orchestrator.py; do
```
- 文件：`install-to-hermes.sh`

### Phase 0 验收命令
```bash
bash scripts/e2e-core-workflow-test.sh
bash scripts/e2e-anti-fake-test.sh
python3 -m py_compile src/skills/hmte/scripts/orchestrator.py
python3 -m py_compile src/skills/hmte/scripts/hmte-audit-flow.py
bash -n scripts/hmte-exec.sh
bash -n src/skills/hmte/scripts/phase_gate.sh
grep -n '\`\`\`yaml' src/skills/hmte/phase-template.md
```

### Phase 0 预计工作量
- 改动文件：7 个，~50 行
- Worker 时间：~15 分钟
- 风险：低

---

## 6. Phase 1 — 启动层可信化

### 新增文件

| 文件 | 类型 |
|------|------|
| `scripts/hmte-kickoff.sh` | 新增 |
| `scripts/hmte-audit-start.sh` | 新增 |

### 6.1 hmte-kickoff.sh

**命令格式**：
```bash
bash scripts/hmte-kickoff.sh "任务描述"           # 默认：有残留则拒绝
bash scripts/hmte-kickoff.sh --archive "任务描述"  # 归档旧 session 后启动
bash scripts/hmte-kickoff.sh --force "任务描述"    # 强制清理（需 HMTE_FORCE=1）
```

**三种模式行为**：

| 模式 | session.json | 运行时残留 | 行为 |
|------|-------------|-----------|------|
| 默认 | 任意 | 有 | **拒绝** |
| 默认 | 不存在 | 无 | **正常启动** |
| --archive | 任意 | 任意 | 归档 → 清空 → 启动 |
| --force | 任意 | 任意 | 强制清空 → 启动（需 HMTE_FORCE=1） |

**脚本逻辑**：

```bash
#!/usr/bin/env bash
set -euo pipefail

RUNTIME_SUBDIRS="instructions evidence verdicts logs delegations errors pids traces"
MODE="default"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive) MODE="archive"; shift ;;
        --force)   MODE="force"; shift ;;
        *)         break ;;
    esac
done

TASK="${1:?Usage: hmte-kickoff.sh [--archive|--force] <task description>}"
CTRL=".phase_control"

# 1. 先创建目录结构 + .gitkeep（幂等，保证空项目/首次使用行为一致）
mkdir -p "$CTRL"
for subdir in $RUNTIME_SUBDIRS; do
    mkdir -p "$CTRL/$subdir"
    touch "$CTRL/$subdir/.gitkeep"
done

# 2. 检查运行时残留（全部 8 个目录）
RESIDUAL_DIRS=""
for subdir in $RUNTIME_SUBDIRS; do
    count=$(find "$CTRL/$subdir" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        RESIDUAL_DIRS="$RESIDUAL_DIRS $subdir($count)"
    fi
done

if [ -f "$CTRL/session.json" ] || [ -n "$RESIDUAL_DIRS" ]; then
    case "$MODE" in
        default)
            echo "ERROR: Cannot start — active session or runtime residuals found." >&2
            [ -f "$CTRL/session.json" ] && echo "  session.json exists" >&2
            [ -n "$RESIDUAL_DIRS" ] && echo "  Residuals:$RESIDUAL_DIRS" >&2
            echo "Use --archive to save and restart, or HMTE_FORCE=1 --force to discard." >&2
            exit 1
            ;;
        archive)
            ARCHIVE_DIR=".phase_control_archive/$(date -u +%Y%m%d_%H%M%S)"
            mkdir -p "$ARCHIVE_DIR"
            cp -a "$CTRL"/. "$ARCHIVE_DIR"/
            echo "Archived to: $ARCHIVE_DIR"
            # 归档后清空运行时产物
            for subdir in $RUNTIME_SUBDIRS; do
                find "$CTRL/$subdir" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
            done
            rm -f "$CTRL/state.json" "$CTRL/session.json"
            ;;
        force)
            if [ "${HMTE_FORCE:-0}" != "1" ]; then
                echo "ERROR: --force requires HMTE_FORCE=1" >&2
                exit 1
            fi
            echo "WARNING: Force mode — discarding previous session data."
            for subdir in $RUNTIME_SUBDIRS; do
                find "$CTRL/$subdir" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
            done
            rm -f "$CTRL/state.json" "$CTRL/session.json"
            ;;
    esac
fi

# 3. 采集 Git 基线
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "null")
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "null")
GIT_DIRTY=false
[ -n "$(git status --short 2>/dev/null)" ] && GIT_DIRTY=true

# 4. 写 session.json（git_status 在 Python 内部通过 subprocess 获取）
python3 - "$CTRL" "$TASK" "$GIT_HEAD" "$GIT_BRANCH" "$GIT_DIRTY" <<'PY'
import json, sys, subprocess
from datetime import datetime, timezone
from pathlib import Path

ctrl, task, head, branch, dirty = sys.argv[1:6]

try:
    r = subprocess.run(['git', 'status', '--short'], capture_output=True, text=True, timeout=10)
    git_status = r.stdout.strip()
except Exception:
    git_status = ""

session = {
    "workflow": "HTE",
    "version": "1.3",
    "mode": "file-instruction",
    "task": task,
    "status": "KICKED_OFF",
    "required_first_action": "Leader must create .phase_control/phases.json before implementation",
    "git_head_at_kickoff": head if head != "null" else None,
    "git_branch_at_kickoff": branch if branch != "null" else None,
    "git_dirty_at_kickoff": dirty == "true",
    "git_status_at_kickoff": git_status,
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "session.json").write_text(
    json.dumps(session, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY

# 5. 写 leader_kickoff.json
python3 - "$CTRL" "$TASK" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, task = sys.argv[1], sys.argv[2]
instr = {
    "role": "Leader",
    "task": task,
    "required_actions": [
        "Read HERMES.md",
        "Read src/skills/hmte/SKILL.md",
        "Inspect project structure",
        "Create .phase_control/phases.json",
        "Create first Worker instruction"
    ],
    "forbidden_actions": [
        "Do not modify business code before phases.json exists",
        "Do not write Worker evidence as Leader",
        "Do not write Verifier verdict as Leader"
    ],
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "instructions", "leader_kickoff.json").write_text(
    json.dumps(instr, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY

# 6. 写初始 state.json
python3 - "$CTRL" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl = Path(sys.argv[1])
state = {
    "status": "KICKED_OFF",
    "current_phase_index": 0,
    "started_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
(ctrl / "state.json").write_text(
    json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY

echo ""
echo "✅ HTE session kicked off"
echo "📄 Session: $CTRL/session.json"
echo "📋 Leader instructions: $CTRL/instructions/leader_kickoff.json"
echo "🔖 Git baseline: $GIT_HEAD ($GIT_BRANCH)"
echo ""
echo "Next: Leader reads leader_kickoff.json, creates phases.json"
```

### 6.2 hmte-audit-start.sh

**5 个状态**（无重叠）：

| 状态 | 条件 |
|------|------|
| `NOT_STARTED` | 无 session.json |
| `KICKED_OFF` | 有 session.json + leader_kickoff.json，无 phases.json |
| `PLANNED` | 有合法 phases.json（含非空 phases 数组），无 Worker instruction |
| `READY_FOR_WORKER` | 有合法 phases.json + 至少一个 Worker instruction |
| `INVALID_START` | JSON 格式错误、缺 leader_kickoff.json、关键字段缺失 |

**phase_id/id 兼容**：优先读 `phase_id`，如果没有则读 `id` 并输出 WARN。

**输出格式**（JSON）：
```json
{
  "status": "READY_FOR_WORKER",
  "checks": [
    {"name": "session.json", "status": "PASS"},
    {"name": "leader_kickoff.json", "status": "PASS"},
    {"name": "phases.json", "status": "PASS"},
    {"name": "phases.json valid", "status": "PASS"},
    {"name": "phases array non-empty", "status": "PASS"},
    {"name": "worker instruction exists", "status": "PASS"},
    {"name": "phase[0].phase_id", "status": "WARN", "detail": "using 'id' instead of 'phase_id' (deprecated)"}
  ],
  "timestamp": "2026-05-29T12:00:00Z"
}
```

**脚本核心**（Python heredoc）：

```bash
#!/usr/bin/env bash
set -euo pipefail
CTRL=".phase_control"
python3 - "$CTRL" <<'PY'
import json, sys, os
from pathlib import Path
from datetime import datetime, timezone

ctrl = Path(sys.argv[1])
checks = []

def check(name, ok, detail=""):
    entry = {"name": name, "status": "PASS" if ok else "FAIL"}
    if detail:
        entry["detail"] = detail
    checks.append(entry)
    return ok

def result(status):
    print(json.dumps({
        "status": status,
        "checks": checks,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }, indent=2))
    sys.exit(0)

# 1. session.json
sp = ctrl / "session.json"
if not sp.exists():
    check("session.json", False, "not found")
    result("NOT_STARTED")
try:
    json.loads(sp.read_text())
    check("session.json", True)
except json.JSONDecodeError as e:
    check("session.json", False, f"invalid JSON: {e}")
    result("INVALID_START")

# 2. leader_kickoff.json
kp = ctrl / "instructions" / "leader_kickoff.json"
if kp.exists():
    check("leader_kickoff.json", True)
else:
    check("leader_kickoff.json", False, "not found")
    result("INVALID_START")

# 3. phases.json
pp = ctrl / "phases.json"
if not pp.exists():
    check("phases.json", False, "not found")
    result("KICKED_OFF")
check("phases.json", True)

try:
    phases_data = json.loads(pp.read_text())
    check("phases.json valid", True)
except json.JSONDecodeError:
    check("phases.json valid", False, "invalid JSON")
    result("INVALID_START")

phases = phases_data.get("phases", [])
if len(phases) == 0:
    check("phases array non-empty", False, "empty")
    result("PLANNED")
check("phases array non-empty", True)

# 4. phase_id/id 兼容检查
for i, p in enumerate(phases):
    pid = p.get("phase_id") or p.get("id")
    if pid is None:
        check(f"phase[{i}].phase_id", False, "missing both phase_id and id")
    elif "phase_id" not in p:
        check(f"phase[{i}].phase_id", True)
        checks[-1]["status"] = "WARN"
        checks[-1]["detail"] = "using 'id' instead of 'phase_id' (deprecated)"

# 5. Worker instructions
instr_dir = ctrl / "instructions"
worker_instrs = [f for f in instr_dir.glob("*_attempt_*_worker.json")]
if worker_instrs:
    check("worker instruction exists", True)
    result("READY_FOR_WORKER")
else:
    check("worker instruction exists", False, "no worker instructions found")
    result("PLANNED")
PY
```

### Instruction 命名规范

统一为：
```
.phase_control/instructions/{phase_id}_attempt_{n}_worker.json
.phase_control/instructions/{phase_id}_attempt_{n}_verifier.json
```

leader_kickoff.json 是特殊指令，不受此约束。

### hmte wrapper

v1.3 只提供独立脚本，wrapper 集成推迟到 v1.4。

### 风险点
- `--force` 误删 → `HMTE_FORCE=1` 双重确认
- `--archive` 目录积累 → 文档建议定期清理

### Phase 1 验收标准

```bash
# 默认拒绝覆盖
bash scripts/hmte-kickoff.sh "task 1"
bash scripts/hmte-kickoff.sh "task 2" 2>&1 | grep "ERROR"
# 应拒绝

# archive 模式
bash scripts/hmte-kickoff.sh --archive "task 2"
test -d .phase_control_archive && echo "PASS"

# force 模式
HMTE_FORCE=1 bash scripts/hmte-kickoff.sh --force "task 3"

# Git 基线
python3 -c "
import json
s = json.load(open('.phase_control/session.json'))
assert s['git_head_at_kickoff'] is not None
assert 'git_status_at_kickoff' in s
print('PASS: git baseline recorded')
"

# audit-start 状态
bash scripts/hmte-audit-start.sh | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'KICKED_OFF'
print('PASS')
"

# 补 phases.json 后
echo '{"phases":[{"phase_id":"p1","name":"T","objective":"T"}]}' > .phase_control/phases.json
bash scripts/hmte-audit-start.sh | python3 -c "
import json, sys; d = json.load(sys.stdin)
assert d['status'] == 'PLANNED'; print('PASS')
"

# phase_id/id 兼容
echo '{"phases":[{"id":"p1","name":"T","objective":"T"}]}' > .phase_control/phases.json
bash scripts/hmte-audit-start.sh | python3 -c "
import json, sys
d = json.load(sys.stdin)
warns = [c for c in d['checks'] if c.get('status') == 'WARN']
assert len(warns) > 0; print('PASS: warns about id')
"
```

### Phase 1 预计工作量
- 新增文件：2 个，~200 行
- Worker 时间：~20 分钟
- 风险：低

---

## 7. Phase 2 — 终局层：final_audit / Release Auditor

### v1.3 决策

**v1.3 不改 orchestrator.py 自动追加 final_audit。** 由 Leader 手动创建 final_audit instruction。推迟到 v1.4。

### 新增文件

| 文件 | 类型 |
|------|------|
| `src/agents/release-auditor.md` | 新增 |
| `src/skills/hmte/final-audit-template.md` | 新增 |

### 7.1 角色分工

| 角色 | 职责 | 产出 |
|------|------|------|
| final_audit Worker | 运行全量检查命令，收集证据 | `evidence/final_audit_attempt_1.json` |
| Release Auditor | 审计 evidence，决定 PASS/FAIL/BLOCK | `verdicts/final_audit_attempt_1.json` |

不存在"一个角色同时写 evidence 和 verdict"的情况。

### 7.2 文件命名（硬规则）

```
.instructions/final_audit_attempt_1_worker.json      ✅
.instructions/final_audit_attempt_1_verifier.json     ✅
.delegations/final_audit_attempt_1_worker.json        ✅
.delegations/final_audit_attempt_1_verifier.json      ✅
.logs/final_audit_attempt_1.commands.jsonl             ✅
.evidence/final_audit_attempt_1.json                   ✅
.verdicts/final_audit_attempt_1.json                   ✅

.evidence/final_audit_attempt_1.evidence.json          ❌ 禁止
.verdicts/final_audit_attempt_1.verdict.json           ❌ 禁止
```

### 7.3 Release Auditor 角色定义

```markdown
---
name: release-auditor
description: 发布前全局审计
tools: Read Grep Glob Bash
disallowedTools: Edit Write Agent
---

# Release Auditor

## 权限说明
Hermes：通过 `delegate_task(toolsets=["terminal","file"])` 获得权限。
verdict 通过 Bash/Python 写入，不修改业务代码。
允许写入：evidence/final_audit_attempt_1.json、verdicts/final_audit_attempt_1.json。

## 必查项（10 项）
1. 原始目标是否完成（对照 session.json + phases.json）
2. 所有普通 phase 是否 PASS verdict
3. 每个 phase 是否有完整链路（command log + evidence + verdict）
4. 所有 phase_gate 是否通过
5. git diff 是否有意外改动（对比 session.json 的 git_head_at_kickoff）
6. README / HERMES.md / SKILL.md 口径一致
7. 旧协议残留检查
8. 全量测试通过
9. residual_risks / verification_gaps 汇总
10. 是否满足交付条件
```

### 7.4 Git 基线对比

Release Auditor 从 session.json 读取基线：
```bash
git diff --stat <git_head_at_kickoff>
git diff --name-only <git_head_at_kickoff>
```

如果 `git_dirty_at_kickoff == true`，在 residual_risks 中标记 `baseline_dirty`。

### 7.5 final_audit verdict 格式

```json
{
  "status": "PASS",
  "phase_id": "final_audit",
  "attempt": 1,
  "timestamp": "ISO8601",
  "scope": "whole_project",
  "adversarial_scorecard": {
    "criteria_passed": [...],
    "criteria_failed": [],
    "global_conflicts": [],
    "evidence_paths": [
      ".phase_control/evidence/final_audit_attempt_1.json",
      ".phase_control/logs/final_audit_attempt_1.commands.jsonl"
    ],
    "residual_risks": [],
    "re_verification_conclusion": "..."
  },
  "next_action": "RELEASE"
}
```

**`evidence_paths` 不得为空**，必须包含 evidence 和 command log 路径。

**`next_action`**：`RELEASE` / `RETURN_TO_LEADER` / `ESCALATE`

### Phase 2 验收标准

```bash
# 构造完整 7 文件链路（使用 make_final_audit_chain helper）
make_final_audit_chain "final_audit" 1 "PASS"

# phase_gate 应 PASS
bash src/skills/hmte/scripts/phase_gate.sh final_audit --attempt 1

# 改为 FAIL，phase_gate 应不放行
make_final_audit_chain "final_audit" 1 "FAIL"
if bash src/skills/hmte/scripts/phase_gate.sh final_audit --attempt 1 2>/dev/null; then
    echo "FAIL: should reject"
else
    echo "PASS: correctly rejected"
fi

# evidence_paths 不为空
python3 -c "
import json
v = json.load(open('.phase_control/verdicts/final_audit_attempt_1.json'))
assert len(v['adversarial_scorecard']['evidence_paths']) >= 2
print('PASS')
"
```

### Phase 2 预计工作量
- 新增文件：2 个，~250 行
- Worker 时间：~25 分钟
- 风险：中

---

## 8. Phase 3 — 委派记录增强

### 新 receipt schema

```json
{
  "phase_id": "phase_a",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_a_attempt_1_worker.json",
  "expected_output_path": ".phase_control/evidence/phase_a_attempt_1.json",
  "tool_call_trace_path": null,
  "observed_delegate_task_id": null,
  "created_at": "ISO8601"
}
```

### 兼容映射

```python
# audit-flow.py 中
trust = receipt.get("delegation_trust_level") or receipt.get("trust_level", "NONE")
```

### OBSERVED 降级策略

| 场景 | 行为 |
|------|------|
| 普通阶段，OBSERVED 缺 trace | 降级 INTENT_ONLY + **WARN** |
| 关键阶段 + `HMTE_REQUIRE_OBSERVED=true`，缺 trace | **FAIL** |

**绝对禁止**：OBSERVED 缺 trace 时以 OBSERVED+PASS 通过。

### 需要修改的文件

| 文件 | 改动 |
|------|------|
| `src/skills/hmte/delegation-receipt-schema.json` | 新增字段 |
| `scripts/hmte-write-receipt.sh` | 区分 Worker/Verifier expected_output_path |
| `src/skills/hmte/scripts/hmte-audit-flow.py` | 兼容 + OBSERVED 降级 |
| `scripts/e2e-core-workflow-test.sh` | 更新 receipt helper |
| `README.md` / `SKILL.md` | 更新 receipt 示例 |

### Phase 3 验收标准

```bash
python3 -c "import json; json.load(open('src/skills/hmte/delegation-receipt-schema.json'))"
# 旧 receipt 兼容 + OBSERVED 降级由 e2e-lifecycle-test.sh L6 覆盖
```

### Phase 3 预计工作量
- 改动文件：6 个，~80 行
- Worker 时间：~20 分钟
- 风险：低

---

## 9. E2E 测试：e2e-lifecycle-test.sh

### 隔离要求

必须在 mktemp 临时项目中运行，不复制真实 `.git`：

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# 只复制测试所需文件
cp -a "$PROJECT_ROOT/scripts" "$TMPDIR/scripts"
cp -a "$PROJECT_ROOT/src" "$TMPDIR/src"
for f in README.md HERMES.md CONTRIBUTING.md CHANGELOG.md LICENSE; do
    [ -f "$PROJECT_ROOT/$f" ] && cp -a "$PROJECT_ROOT/$f" "$TMPDIR/$f"
done

# 创建 .phase_control 结构
mkdir -p "$TMPDIR/.phase_control"
for d in instructions evidence verdicts logs delegations errors pids traces; do
    mkdir -p "$TMPDIR/.phase_control/$d"
    touch "$TMPDIR/.phase_control/$d/.gitkeep"
done

# 初始化临时 git repo（设置本地 identity）
cd "$TMPDIR"
if git init -q 2>/dev/null; then
    git config user.email "hte-test@example.local"
    git config user.name "HTE Test"
    git add -A 2>/dev/null || true
    git commit -m "init" --allow-empty -q 2>/dev/null || true
    GIT_AVAILABLE=true
else
    GIT_AVAILABLE=false
    echo "WARN: git not available, some tests degraded"
fi

# 所有路径基于 $TMPDIR
CTRL="$TMPDIR/.phase_control"
SCRIPTS="$TMPDIR/scripts"
SKILL="$TMPDIR/src/skills/hmte"
RUNTIME_SUBDIRS="instructions evidence verdicts logs delegations errors pids traces"
```

### 统一 reset 函数

```bash
reset_runtime() {
    for subdir in $RUNTIME_SUBDIRS; do
        find "$CTRL/$subdir" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
    done
    rm -f "$CTRL/state.json" "$CTRL/session.json" "$CTRL/phases.json"
    rm -rf "$TMPDIR/.phase_control_archive/"
}
```

### make_final_audit_chain helper

接受 4 个参数：`$1=phase_id` `$2=attempt` `$3=verdict_status` `$4=receipt_type`

- `$3`：`PASS` / `FAIL` / `BLOCK`
- `$4`：`NORMAL` / `OBSERVED_NO_TRACE`

创建完整 7 文件链路：
1. Worker instruction
2. Verifier instruction
3. Worker receipt
4. Verifier receipt
5. Command log（通过 hmte-exec）
6. Evidence
7. Verdict

receipt 必须包含 `leader_instruction_path` 和 `expected_output_path`。

PASS verdict 的 `evidence_paths` 不得为空。

### 测试用例

| ID | 名称 | 操作 | 预期 |
|----|------|------|------|
| L1 | Kickoff 创建启动文件 | `hmte-kickoff.sh "test"` | session.json + leader_kickoff.json 存在且合法 |
| L2 | Audit Start 未规划状态 | 无 phases.json | 输出 KICKED_OFF |
| L3 | Audit Start 可委派状态 | 补 phases.json + Worker instruction | 输出 READY_FOR_WORKER |
| L4 | Final Audit PASS | `make_final_audit_chain ... PASS` → phase_gate | exit 0，evidence_paths 非空 |
| L5 | Final Audit FAIL | `make_final_audit_chain ... FAIL` → phase_gate | exit 1，7 文件全存在 |
| L6a | 旧 receipt 兼容 | 完整链路 + `trust_level` → audit-flow | overall=PASS |
| L6b | 新 receipt 兼容 | 完整链路 + `delegation_trust_level` → audit-flow | overall=PASS |
| L6c | OBSERVED 无 trace | 完整链路 + OBSERVED + 无 trace → audit-flow | 绝不 OBSERVED+PASS |

每个测试开头必须调用 `reset_runtime`，互相独立不污染。

### L5 详细说明

L5 复用 `make_final_audit_chain` helper（与 L4 相同），只是 verdict.status=FAIL。确保失败原因是 verdict.status=FAIL，而不是缺文件。L5 运行后必须验证 7 个文件都存在。

### L6 详细说明

L6 不得假设 audit-flow --json 顶层字段。断言使用多层检查：

```bash
# 获取结果
result=$(python3 "$SKILL/scripts/hmte-audit-flow.py" "$P" "$A" --json 2>/dev/null || echo '{}')

# 多层断言
overall=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('overall','FAIL'))")
trust=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('trust_level','NONE'))")

# L6c 核心断言：绝不能 OBSERVED+PASS
if [ "$trust" = "OBSERVED" ] && [ "$overall" = "PASS" ]; then
    fail "L6c: OBSERVED without trace MUST NOT pass as OBSERVED"
fi
```

L6 必须覆盖 worker 和 verifier receipt 的 OBSERVED_NO_TRACE 情况。

### Phase 1-2-3 验收中也要覆盖 r2-5（residual 拒绝）全部 8 个目录

kickoff residual 拒绝测试应分别验证每个目录：

```bash
# 对 8 个目录分别测试残留拒绝
for subdir in $RUNTIME_SUBDIRS; do
    reset_runtime
    touch "$CTRL/$subdir/test_marker.tmp"
    if bash "$SCRIPTS/hmte-kickoff.sh" "test" 2>/dev/null; then
        fail "kickoff should reject residual in $subdir"
    else
        pass "kickoff correctly rejects residual in $subdir"
    fi
    rm -f "$CTRL/$subdir/test_marker.tmp"
done
```

---

## 10. 文档更新计划

| 文件 | 改动 |
|------|------|
| `README.md` | Roadmap v1.3、kickoff/audit-start/final_audit 说明 |
| `CHANGELOG.md` | 新增 `[1.3.0]` 条目 |
| `HERMES.md` | 工作流：kickoff → phases → exec → audit → final_audit |
| `src/skills/hmte/SKILL.md` | 新增 kickoff/audit-start/final_audit 用法 |
| `CONTRIBUTING.md` | 新增 e2e-lifecycle-test.sh |
| `src/agents/release-auditor.md` | 新增 |
| `src/skills/hmte/final-audit-template.md` | 新增 |

---

## 11. 向后兼容策略

| 兼容项 | 策略 |
|--------|------|
| 旧 receipt（trust_level） | audit-flow.py 兼容两个字段名 |
| 旧 phases.json 格式 | 不变 |
| 旧 verdict / evidence / command log | 不变 |
| hmte-exec.sh / phase_gate.sh | 不变 |
| orchestrator.py | v1.3 不改 |

---

## 12. 回滚策略

| Phase | 回滚方式 |
|-------|---------|
| Phase 0 | git revert |
| Phase 1 | 删除 hmte-kickoff.sh + hmte-audit-start.sh |
| Phase 2 | 删除 release-auditor.md + final-audit-template.md |
| Phase 3 | 恢复旧 receipt schema |

---

## 13. 最终验收命令

```bash
# Phase 0
bash scripts/e2e-core-workflow-test.sh
bash scripts/e2e-anti-fake-test.sh
python3 -m py_compile src/skills/hmte/scripts/orchestrator.py
python3 -m py_compile src/skills/hmte/scripts/hmte-audit-flow.py
bash -n scripts/hmte-exec.sh
bash -n src/skills/hmte/scripts/phase_gate.sh

# Phase 1
bash scripts/hmte-kickoff.sh "验收测试"
test -f .phase_control/session.json
bash scripts/hmte-audit-start.sh

# Phase 2
bash src/skills/hmte/scripts/phase_gate.sh final_audit --attempt 1

# Phase 3
python3 -c "import json; json.load(open('src/skills/hmte/delegation-receipt-schema.json'))"

# 全量
bash scripts/e2e-core-workflow-test.sh
bash scripts/e2e-anti-fake-test.sh
bash scripts/e2e-lifecycle-test.sh
python3 -m py_compile src/skills/hmte/scripts/orchestrator.py
python3 -m py_compile src/skills/hmte/scripts/hmte-audit-flow.py
bash -n scripts/hmte-kickoff.sh
bash -n scripts/hmte-audit-start.sh
bash -n scripts/hmte-exec.sh
bash -n src/skills/hmte/scripts/phase_gate.sh
```

---

## 14. 预计工作量

| Phase | 优先级 | 文件数 | 新增行数 | Worker 时间 | 风险 |
|-------|--------|--------|---------|------------|------|
| Phase 0 | P0 | 7 | ~50 | ~15min | 低 |
| Phase 1 | P0 | 2 新增 | ~200 | ~20min | 低 |
| Phase 2 | P0 | 2 新增 | ~250 | ~25min | 中 |
| Phase 3 | P1 | 6 | ~80 | ~20min | 低 |
| E2E | P0 | 1 新增 | ~300 | ~25min | 低 |
| 文档 | P0 | 7 | ~100 | ~10min | 低 |

**总计**：~25 文件，~980 行，~115 分钟。

**建议执行顺序**：Phase 0 → Phase 1 → Phase 2 → Phase 3 → E2E → 文档

---

## 15. 执行约束汇总（r2 + r3 + r4）

| # | 约束 | 来源 |
|---|------|------|
| r2-1 | kickoff 默认检查全部 8 个 RUNTIME_SUBDIRS 残留 | r2 |
| r2-2 | instruction 命名统一 `_attempt_{n}_role.json` | r2 |
| r2-3 | final_audit 文件名不得加 `.evidence.` / `.verdict.` 中缀 | r2 |
| r2-4 | L4 必须创建完整 7 文件链路 | r2 |
| r2-5 | PASS verdict evidence_paths 不得为空 | r2 |
| r2-6 | L6 必须构造完整链路后跑 audit-flow | r2 |
| r2-7 | session.json 增加 git_status_at_kickoff | r2 |
| r2-8 | E2E 每个测试独立 reset | r2 |
| r2-9 | audit-start 兼容 id 字段并输出 warning | r2 |
| r3-1 | E2E 不得破坏真实 .phase_control（mktemp） | r3 |
| r3-2 | 运行时目录列表统一为 8 个 | r3 |
| r3-3 | L5 必须构造完整 7 文件链路 | r3 |
| r3-4 | L6 不得假设 audit-flow JSON 字段 | r3 |
| r3-5 | git_status 在 Python 内部获取 | r3 |
| r4-1 | mktemp 不复制 .git | r4 |
| r4-2 | 临时 git 设置 identity + 允许 null | r4 |
| r4-3 | kickoff residual 检查前先创建目录 | r4 |
| r4-4 | OBSERVED 无 trace 不得 OBSERVED+PASS | r4 |
