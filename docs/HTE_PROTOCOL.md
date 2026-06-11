# Protocol Specification

*TriAgentFlow internal protocol. Formerly HTE.*

**Version**: 2.0  
**Status**: Authoritative Reference  
**Base**: v1.8 legacy protocol specification, with v2.0 Plan-Grounded Audit Governance extension

本文档是 TriAgentFlow / TAF 文件协议的权威规范（hmte 为历史命令前缀）。README、HERMES、SKILL 等文档引用本规范，不重复完整协议细节。

**v1.8 增量入口**（完整规范见对应文档）:
- [PROJECT_BOUNDARIES.md](PROJECT_BOUNDARIES.md) — 五条宪法具象化，项目边界和设计原则
- [RUNTIME_ENTRY.md](RUNTIME_ENTRY.md) — 主路径 vs 辅助路径，manual delegation fallback
- [PHASES_SCHEMA.md](PHASES_SCHEMA.md) — phases.json canonical schema（phase_id/goal）
- [VALIDATION_MAP.md](VALIDATION_MAP.md) — 改什么验证什么 + Gate Test Policy
- [COMPLEXITY_BUDGET.md](COMPLEXITY_BUDGET.md) — 文件/脚本/依赖预算 + Release Governance
- [PLANNING_PROTOCOL.md](PLANNING_PROTOCOL.md) — 文件化规划层

**v2.0 增量入口**（Plan-Grounded Audit Governance）:
- [PLAN_CONTRACT.md](PLAN_CONTRACT.md) — Plan Contract: 计划锁定 + amendment 跟踪
- [PLAN_LOCK.md](PLAN_LOCK.md) — Plan Lock: 计划哈希 + 防篡改
- [PLAN_TO_DELEGATION_FIDELITY.md](PLAN_TO_DELEGATION_FIDELITY.md) — Fidelity: Worker 忠实执行计划
- [VERIFIER_MANDATE.md](VERIFIER_MANDATE.md) — Mandate: 审计范围必须覆盖变更
- [PLAN_COVERAGE_GATE.md](PLAN_COVERAGE_GATE.md) — Coverage: 计划项完整覆盖验证
- [ANOMALY_LEDGER.md](ANOMALY_LEDGER.md) — Anomaly: 异常记录 + disposition 追踪
- [TEST_DISPOSITION_GATE.md](TEST_DISPOSITION_GATE.md) — Disposition: 跳过/失败测试必须有说明
- [PASS_CONTRADICTION.md](PASS_CONTRADICTION.md) — Contradiction: 检测声明与证据冲突
- [ZERO_FINDING.md](ZERO_FINDING.md) — Zero-Finding: 零发现必须提供证据锚点
- [../VALIDATION_SUMMARY_v2.0.md](../VALIDATION_SUMMARY_v2.0.md) — v2.0 验证摘要 (62/62 PASS)

**v1.8 不改变 v1.7 parallel gate 语义**：
- `execution_mode: parallel_safe` 保持不变
- `parallel_workers` 字段保持不变
- parallel_gate_check.py 逻辑保持不变
- v1.8 只新增治理层文档和验证脚本，不修改核心门禁

---

## 1. Evidence Bundle Format

Worker 在每个阶段结束时提交 evidence bundle：

**路径**: `.phase_control/evidence/{phase_id}_attempt_{n}.json`

**必需字段** (✅ Required for phase_gate):
- `phase_id` (string): 阶段唯一标识符 - ✅ Required
- `attempt` (integer): 尝试次数（从1开始）- ✅ Required
- `status` (string): 证据状态（"completed", "partial", "blocked"）- ✅ Required
- `worker_name` (string): Worker agent 名称 - ✅ Required
- `goal_summary` (string): 阶段目标简述 - ✅ Required
- `planned_output` (string): 预期输出 - ✅ Required
- `changed_files` (array[string]): 创建或修改的文件列表 - ✅ Required
- `commands_run` (array[string]): 执行的命令列表 - ✅ Required
- `command_exit_codes` (array[integer]): 每个命令的退出码（0=成功）- ✅ Required
- `generated_at` (string, ISO 8601): 证据生成时间戳，**用于 phase_gate timeline check** - ✅ Required

**可选字段**:
- `command_log_path` (string): 命令日志路径
- `test_results` (object): `{total, passed, failed, skipped}`
- `lint_results` (object): `{errors, warnings}`
- `build_results` (object): `{success, errors[]}`
- `diff_summary` (string): 变更摘要
- `artifact_paths` (array[string]): 关键产物路径
- `unresolved_risks` (array[string]): 未解决的风险
- `verification_gaps` (array[string]): 无法验证的方面

**v1.6 增强字段** (可选):
- `evidence_type` (enum): `"INTENT_ONLY"` | `"OBSERVED"` - 标识证据来源
- `observations` (array[object]): 观察到的执行事实，格式 `[{event, timestamp, data}]`

**示例**:
```json
{
  "phase_id": "implement_auth",
  "attempt": 1,
  "status": "completed",
  "worker_name": "phase-executor",
  "goal_summary": "实现登录接口",
  "planned_output": "可工作的登录API + 测试",
  "changed_files": ["src/api/auth.js", "tests/auth.test.js"],
  "command_log_path": ".phase_control/logs/implement_auth_attempt_1.commands.jsonl",
  "commands_run": ["npm test"],
  "command_exit_codes": [0],
  "test_results": {"total": 12, "passed": 12, "failed": 0},
  "unresolved_risks": ["生产环境 JWT secret 需要单独配置"],
  "verification_gaps": [],
  "generated_at": "2026-06-02T13:03:00Z"
}
```

**Schema**: `src/skills/hmte/evidence-schema.json`

---

## 2. Verdict Format

Verifier 输出 JSON verdict：

**路径**: `.phase_control/verdicts/{phase_id}_attempt_{n}.json`

**必需字段** (✅ Required for phase_gate):
- `status` (enum): `"PASS"` | `"FAIL"` | `"BLOCK"` - ✅ Required  
  **重要**: 顶层字段名必须是 `status`，不是 `verdict`
- `phase_id` (string): 必须与 evidence 匹配 - ✅ Required
- `attempt` (integer): 必须与 evidence 匹配 - ✅ Required
- `timestamp` (string, ISO 8601): verdict 生成时间，**用于 phase_gate timeline check** - ✅ Required
- `adversarial_scorecard` (object): 详见下方 - ✅ Required

**可选字段**:
- `confidence` (enum): `"high"` | `"medium"` | `"low"`
- `next_action` (enum): `"NEXT_PHASE"` | `"RETRY"` | `"BLOCK"`
- `evidence_sha256` (string, 64 hex chars): evidence 文件 SHA256（防篡改）
- `command_log_sha256` (string, 64 hex chars): command log SHA256（防篡改）

**adversarial_scorecard 必需字段** (✅ Required for phase_gate - P0-4):
- `criteria_passed` (array[object]): 通过的验收标准，每项包含 `{criterion, evidence}`，PASS时至少1条 - ✅ Required
- `criteria_failed` (array[object]): 未通过的验收标准，每项包含 `{criterion, reason}`，PASS时必须为空 - ✅ Required
- `evidence_paths` (array[string]): 审计依据的证据文件路径，至少包含 evidence 和 command log - ✅ Required
- `residual_risks` (array[string]): 已知但不阻断的风险（无风险时写 `["none"]`）- ✅ Required
- `re_verification_conclusion` (string): 复验结论（≥20字符）- ✅ Required
- `verification_method` (enum): `"manual_review"` | `"automated_test"` | `"cross_check"` | `"code_review"` | `"docs_review"` | `"config_review"` - ✅ Required
- `risk_disposition` (array[object]): 风险处置，每项包含 `{risk, disposition, reason}`，disposition 必须是 `"accepted"` | `"mitigated"` | `"blocked"` | `"deferred"` - ✅ Required
- `independently_verified_files` (array[string]): Verifier 独立验证的文件路径（不得指向 `.phase_control/` 内部文件）- ✅ Required
- `command_log_checked` (boolean): Verifier 是否检查 command log（PASS 必须 true）- ✅ Required
- `diff_checked` (boolean): Verifier 是否检查 git diff（PASS 必须 true）- ✅ Required
- `evidence_consistency_checked` (boolean): Verifier 是否检查 evidence 一致性（PASS 必须 true）- ✅ Required

**示例**:
```json
{
  "status": "PASS",
  "phase_id": "implement_auth",
  "attempt": 1,
  "timestamp": "2026-06-02T13:05:00Z",
  "confidence": "high",
  "adversarial_scorecard": {
    "criteria_passed": [
      {
        "criterion": "单元测试通过",
        "evidence": ".phase_control/logs/implement_auth_attempt_1.commands.jsonl: npm test exit_code=0"
      }
    ],
    "criteria_failed": [],
    "evidence_paths": [
      ".phase_control/evidence/implement_auth_attempt_1.json",
      ".phase_control/logs/implement_auth_attempt_1.commands.jsonl"
    ],
    "verification_method": "cross_check",
    "risk_disposition": [
      {
        "risk": "生产环境 JWT secret 需要单独配置",
        "disposition": "accepted",
        "reason": "部署阶段由环境变量注入，不阻塞当前阶段验收"
      }
    ],
    "residual_risks": ["生产环境 JWT secret 需要单独配置"],
    "re_verification_conclusion": "已复核 evidence、command log 和变更文件，验收标准均有证据支撑。",
    "independently_verified_files": ["src/api/auth.js", "tests/auth.test.js"],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  }
}
```

**Schema**: `src/skills/hmte/verdict-schema.json`

---

## 3. Phase Gate Rules

`phase_gate.sh` 检查阶段是否可以继续：

**检查项**:
1. **文件完整性**: instruction、receipt、command log、evidence、verdict 是否存在
2. **ID 一致性**: phase_id 和 attempt 在所有文件中必须一致
3. **Receipt 验证**: Worker 和 Verifier 的 delegation receipt 存在且有效
4. **Command Log**: JSONL 格式有效，至少1条记录
5. **Evidence**: JSON 有效，包含必需字段
6. **Verdict**: 
   - Status 必须是 PASS/FAIL/BLOCK
   - PASS 时 criteria_failed 必须为空
   - PASS 时 criteria_passed 至少1条
7. **P0-4 Verifier Minimum Audit**: PASS verdict 必须包含所有 P0 必需字段（见第2节）
8. **Timeline**: Worker `delegated_at` ≤ Evidence `generated_at` ≤ Verdict `timestamp`  
   **Required fields for timeline check**:
   - Worker receipt: `delegated_at`
   - Evidence: `generated_at` (or `timestamp` as fallback)
   - Verdict: `timestamp`
9. **SHA256 (可选)**: 如设置 `HMTE_STRICT_HASH=true`，验证 evidence_sha256 和 command_log_sha256

**放行条件**:
- Verdict status = PASS
- 所有 P0 检查通过
- 无阻断性错误

**退出码**:
- `0`: PASS，可以继续
- `1`: FAIL/BLOCK，阻断

---

## 4. Leader Jail Constraints

Leader 不得直接修改项目文件。所有项目文件变更必须通过 Worker 执行并记录。

**检查点**: `hmte-leader-jail.sh`

**规则**:
1. 项目文件（非 `.phase_control/`）如有变更，必须：
   - 在某个 phase 的 evidence.changed_files 中声明
   - 在对应 command log 中有相关命令
   - 有完整的 Worker receipt
   - 有 Verifier verdict 批准
2. 禁止 Leader 使用 `echo >`, `sed -i`, `vim` 等直接修改项目文件
3. `.phase_control/` 目录内的协议文件由 Leader 管理，不受此限制

**验证方式**:
```bash
bash scripts/hmte-leader-jail.sh
```

---

## 5. Goalpost Lock Protocol

SHA-256 锁定验收标准，防止后续弱化、删除或新增 phase。

**锁定文件**: `.phase_control/goal_lock.json`

**格式**:
```json
{
  "phases_hash": "64-character-sha256-of-phases.json",
  "locked_at": "2026-06-02T10:00:00Z",
  "locked_by": "Leader",
  "goal_summary": "实现用户认证模块"
}
```

**检查点**: `hmte-goal-lock.sh` 和 `hmte-final-check.sh`

**规则**:
1. 锁定后，`phases.json` 不得修改，除非：
   - 有 amendment 授权文件（`.phase_control/amendments/{timestamp}_{phase}_{action}.json`）
   - Amendment 包含 `reason`（≥20字符）、`action`（add_phase/delete_phase/modify_criteria）
2. 检测项：
   - Phase 删除
   - Criteria 删除或弱化
   - Phase 新增（无 amendment）

---

## 6. Verifier Minimum Audit (P0-4)

PASS verdict 必须包含以下字段，否则 phase_gate 阻断：

| 字段 | 类型 | 要求 |
|------|------|------|
| `verification_method` | enum | 必须是枚举值之一 |
| `risk_disposition` | array[object] | 每项包含 risk/disposition/reason |
| `re_verification_conclusion` | string | ≥20 字符 |
| `independently_verified_files` | array[string] | 非空，文件必须存在，**不得指向 `.phase_control/` 内部文件** |
| `evidence_paths` | array[string] | 包含 evidence 和 command log |
| `command_log_checked` | boolean | true |
| `diff_checked` | boolean | true |
| `evidence_consistency_checked` | boolean | true |
| `criteria_passed` | array[object] | 至少1条 |
| `criteria_failed` | array | 必须为空 |

**重要约束**:
- `independently_verified_files` 只能指向**项目产物文件**（如 `src/`, `tests/`, `docs/` 等）
- `.phase_control/` 内部文件（phases.json, evidence, verdict, command log 等）是协议控制平面文件，可以作为 `evidence_paths` 检查，但不能算作"独立验证的项目文件"
- 如果 Verifier 只验证了协议文件而未检查任何项目产物，phase_gate 将拒绝

**豁免**: `final_audit` 阶段可以豁免部分检查（如 independently_verified_files 可为空）

---

## 7. Receipt Format

Delegation receipt 记录 Leader 委派意图。

**路径**: `.phase_control/delegations/{phase_id}_attempt_{n}_{worker|verifier}.json`

**必需字段** (✅ Required for phase_gate):
- `phase_id` (string) - ✅ Required
- `attempt` (integer) - ✅ Required
- `role` (enum): `"worker"` | `"verifier"` - ✅ Required
- `delegation_trust_level` (enum): `"INTENT_ONLY"` | `"OBSERVED"` - ✅ Required (or legacy `trust_level`)
- `delegation_method` (string): `"delegate_task"` 或 `"manual_file_instruction"` - ✅ Required
- `delegated_at` (string, ISO 8601): 委派时间，**用于 phase_gate timeline check** - ✅ Required
- `timestamp` (string, ISO 8601): receipt 生成时间（可与 delegated_at 相同）- ✅ Required

**可选字段**:
- `leader_instruction_path` (string)
- `expected_output_path` (string)
- `tool_call_trace_path` (string): OBSERVED 时包含 trace
- `observed_delegate_task_id` (string): OBSERVED 时包含 task ID

**兼容性**: 支持旧格式的 `trust_level` 字段（向后兼容）

---

## 8. File Naming Conventions

**详细规范**: 参见 `docs/FILE_NAMING.md`

**核心规则**:
- Phase ID: `^[A-Za-z0-9_-]+$`（禁止路径穿越）

### Sequential Phase Artifacts

| Artifact Type | Path Pattern | Example |
|--------------|--------------|---------|
| Worker Instruction | `.phase_control/instructions/{phase_id}_attempt_{n}_worker.json` | `phase_a_attempt_1_worker.json` |
| Worker Receipt | `.phase_control/delegations/{phase_id}_attempt_{n}_worker.json` | `phase_a_attempt_1_worker.json` |
| Verifier Instruction | `.phase_control/instructions/{phase_id}_attempt_{n}_verifier.json` | `phase_a_attempt_1_verifier.json` |
| Verifier Receipt | `.phase_control/delegations/{phase_id}_attempt_{n}_verifier.json` | `phase_a_attempt_1_verifier.json` |
| Command Log | `.phase_control/logs/{phase_id}_attempt_{n}.commands.jsonl` | `phase_a_attempt_1.commands.jsonl` |
| Evidence Bundle | `.phase_control/evidence/{phase_id}_attempt_{n}.json` | `phase_a_attempt_1.json` |
| Verdict | `.phase_control/verdicts/{phase_id}_attempt_{n}.json` | `phase_a_attempt_1.json` |

### Parallel Phase Artifacts (parallel_safe mode)

| Artifact Type | Path Pattern | Example |
|--------------|--------------|---------|
| Worker Shard Instruction | `.phase_control/instructions/{phase_id}_{worker_id}_attempt_{n}_worker.json` | `phase_c_impl-core_attempt_1_worker.json` |
| Worker Shard Receipt | `.phase_control/delegations/{phase_id}_{worker_id}_attempt_{n}_worker.json` | `phase_c_impl-core_attempt_1_worker.json` |
| Worker Shard Command Log | `.phase_control/logs/{phase_id}_{worker_id}_attempt_{n}.commands.jsonl` | `phase_c_impl-core_attempt_1.commands.jsonl` |
| Worker Shard Evidence | `.phase_control/evidence/{phase_id}_{worker_id}_attempt_{n}.json` | `phase_c_impl-core_attempt_1.json` |
| Verifier Instruction | `.phase_control/instructions/{phase_id}_attempt_{n}_verifier.json` | `phase_c_attempt_1_verifier.json` |
| Verifier Receipt | `.phase_control/delegations/{phase_id}_attempt_{n}_verifier.json` | `phase_c_attempt_1_verifier.json` |
| Verdict (Join) | `.phase_control/verdicts/{phase_id}_attempt_{n}.json` | `phase_c_attempt_1.json` |

**Key differences**:
- Sequential: Single worker, no `worker_id` in filenames
- Parallel: Multiple workers, each with unique `worker_id` prefix in evidence/command-log paths
- Verifier artifacts (instruction, receipt, verdict) use the same naming pattern for both modes

---

## 9. Controlled Parallelism (v1.7)

### 9.1 Execution Modes

Phases support two `execution_mode` values:

- **sequential** (default, backward-compatible): One Worker, one Verifier per phase. v1.6 behavior unchanged.
- **parallel_safe**: Multiple Worker Shards within a single phase. Each shard has isolated scope. Verifier performs join verification across all shard evidence.

### 9.2 phases.json — Parallel Phase Schema

A `parallel_safe` phase extends the standard phase definition:

```json
{
  "phases": [
    {
      "phase_id": "c3",
      "goal": "Implement feature X with isolated sub-tasks",
      "execution_mode": "parallel_safe",
      "parallel_workers": [
        {
          "worker_id": "impl-core",
          "scope": "Implement core logic",
          "forbidden_paths": ["src/api/**", "tests/api/**"]
        },
        {
          "worker_id": "impl-api",
          "scope": "Implement API layer",
          "forbidden_paths": ["src/core/**", "tests/core/**"]
        }
      ],
      "acceptance_criteria": ["Both sub-tasks complete", "No file overlap"]
    }
  ]
}
```

### 9.3 Worker Shard Semantics

- Each Worker Shard is a standard Worker Agent instance with a unique `worker_id`.
- `worker_id` MUST match `^[A-Za-z0-9_-]{1,64}$`.
- Each shard writes its own evidence to `.phase_control/evidence/{phase_id}_{worker_id}_attempt_{n}.json`.
- Each shard writes its own command log to `.phase_control/logs/{phase_id}_{worker_id}_attempt_{n}.commands.jsonl`.
- Each shard MUST NOT modify files in its own `forbidden_paths` (enforced by checking `changed_files` vs `forbidden_paths`). To prevent Worker A from modifying Worker B's domain, Leader must explicitly add B's paths to Worker A's `forbidden_paths`.
- Shards MUST NOT modify the same files as other shards (no `changed_files` overlap).

### 9.4 Verifier Join Verification

In `parallel_safe` mode, the Verifier MUST:

1. Read ALL shard evidence files for the phase.
2. Read ALL shard command logs for the phase.
3. Verify each shard independently against acceptance criteria.
4. Check for `changed_files` overlap between shards.
5. Check that each shard's `changed_files` do not hit its own `forbidden_paths`.
6. Write a verdict with `join_verification` block (see §9.5).

### 9.5 Verdict Format — Join Block

For `parallel_safe` phases, the verdict JSON MUST include a `join_verification` object:

**Important**: `join_verification` is a verdict block name, NOT a `verification_method` value. For parallel_safe phases, use `verification_method: "cross_check"` or `"manual_review"` in the adversarial_scorecard.

**Required fields for parallel_safe verdict** (✅ Required for phase_gate):
- `evidence_paths` (array[string]): ALL shard evidence paths - ✅ Required
- `command_log_paths` (array[string]): ALL shard command log paths - ✅ Required
- `join_verification` (object): Join verification results - ✅ Required
  - `all_worker_evidence_checked` (boolean): Must be `true` - ✅ Required
  - `all_command_logs_checked` (boolean): Must be `true` - ✅ Required
  - `missing_shards` (array): Must be `[]` (empty) - ✅ Required
  - `per_shard_results` (array[object]): Results for each shard - ✅ Required
  - `changed_files_overlap` (array): Files modified by multiple shards (should be empty for PASS) - Optional but recommended

**Example**:

```json
{
  "status": "PASS",
  "phase_id": "c3",
  "attempt": 1,
  "timestamp": "...",
  "adversarial_scorecard": { "..." : "..." },
  "join_verification": {
    "all_worker_evidence_checked": true,
    "all_command_logs_checked": true,
    "missing_shards": [],
    "per_shard_results": [
      {"worker_id": "impl-core", "evidence_status": "PASS", "changed_files_count": 5},
      {"worker_id": "impl-api", "evidence_status": "PASS", "changed_files_count": 3}
    ]
  },
  "evidence_paths": [
    ".phase_control/evidence/c3_impl-core_attempt_1.json",
    ".phase_control/evidence/c3_impl-api_attempt_1.json"
  ],
  "command_log_paths": [
    ".phase_control/logs/c3_impl-core_attempt_1.commands.jsonl",
    ".phase_control/logs/c3_impl-api_attempt_1.commands.jsonl"
  ]
}
```

### 9.6 Phase Gate — Join Gate Hard Checks (12 items)

For `parallel_safe` phases, `phase_gate.sh` MUST verify ALL of the following:

| # | Check | Description |
|---|-------|-------------|
| 1 | worker_id legal | Each `worker_id` in `parallel_workers` matches `^[A-Za-z0-9_-]{1,64}$` |
| 2 | Evidence exists | Each `expected_evidence_path` exists and is valid JSON |
| 3 | Command log valid | Each `expected_command_log_path` exists, is non-empty, is valid JSONL, and every entry has `phase_id`, `attempt`, `worker_id`, `command`, `exit_code`, `runner`, `started_at`, `ended_at` |
| 4 | Evidence coverage | `verdict.evidence_paths` covers ALL expected evidence paths |
| 5 | Command log coverage | `verdict.command_log_paths` covers ALL expected command log paths |
| 6 | join_verification present | `verdict.join_verification` object exists |
| 7 | all_worker_evidence_checked | `verdict.join_verification.all_worker_evidence_checked === true` |
| 8 | all_command_logs_checked | `verdict.join_verification.all_command_logs_checked === true` |
| 9 | missing_shards empty | `verdict.join_verification.missing_shards` is `[]` |
| 10 | No forbidden_paths violation | Each worker's `changed_files` must not contain paths from that worker's own `forbidden_paths` |
| 11 | No changed_files overlap | No two workers share any file in `changed_files` |
| 12 | No blocked/partial with PASS | If any worker evidence `status` is `BLOCKED`/`PARTIAL`/`FAIL`, a `PASS` verdict is invalid |

**Additional consistency checks:**
- If `execution_mode` is missing/`sequential` but `parallel_workers` is non-empty → FAIL.
- If `execution_mode` is `parallel_safe` but `parallel_workers` is missing/empty → FAIL.
- `runner` MUST be `"hmte exec"` for every shard command log entry.
- Each shard command log entry MUST match the current `phase_id`, `attempt`, and shard `worker_id`.

### 9.7 Final Check — Shard-Aware Release Gate

`hmte-final-check.sh` MUST remain the final completion gate for both sequential and `parallel_safe` phases.

For `sequential` phases, final-check keeps the legacy 7-file chain:

```text
.phase_control/instructions/{phase_id}_attempt_{n}_worker.json
.phase_control/delegations/{phase_id}_attempt_{n}_worker.json
.phase_control/instructions/{phase_id}_attempt_{n}_verifier.json
.phase_control/delegations/{phase_id}_attempt_{n}_verifier.json
.phase_control/logs/{phase_id}_attempt_{n}.commands.jsonl
.phase_control/evidence/{phase_id}_attempt_{n}.json
.phase_control/verdicts/{phase_id}_attempt_{n}.json
```

For `parallel_safe` phases, final-check MUST NOT require a legacy single worker evidence/log/receipt. It MUST check:

```text
.phase_control/instructions/{phase_id}_attempt_{n}_verifier.json
.phase_control/delegations/{phase_id}_attempt_{n}_verifier.json
.phase_control/verdicts/{phase_id}_attempt_{n}.json
```

And for every `parallel_workers[].worker_id`:

```text
.phase_control/instructions/{phase_id}_{worker_id}_attempt_{n}_worker.json
.phase_control/delegations/{phase_id}_{worker_id}_attempt_{n}_worker.json
.phase_control/logs/{phase_id}_{worker_id}_attempt_{n}.commands.jsonl
.phase_control/evidence/{phase_id}_{worker_id}_attempt_{n}.json
```

After file-chain checks, final-check MUST call:

```bash
# 用户手动调用优先使用项目根目录 wrapper
bash scripts/phase_gate.sh <phase_id> --attempt <n>

# final-check 内部可通过 HMTE_SKILL_DIR 定位实际实现
# bash src/skills/hmte/scripts/phase_gate.sh <phase_id> --attempt <n>
```

### 9.8 Schema Policy

`verdict-schema.json` 当前不强制要求 `join_verification` 字段。parallel join_verification 由 `phase_gate.sh` → `parallel_gate_check.py` 程序化强校验。如未来需要 strict schema，将在 v1.8 单独处理。

### 9.9 Backward Compatibility

- `sequential` phases (or phases without `execution_mode`) behave exactly as v1.6.
- No existing verdict format is changed. `join_verification` is only required for `parallel_safe` phases.
- `evidence_paths` and `command_log_paths` are optional in `sequential` mode verdicts.

## 10. Legacy Hermes Mapping

TriAgentFlow / TAF 三 Agent 模型在 Hermes 中的 legacy mapping：

| TAF 角色 | Hermes Agent 文件 | delegate_task 角色参数 | 职责 |
|---------|------------------|---------------------|------|
| **Leader** | `src/agents/master-planner.md` | `"Leader"` | 规划阶段、维护状态、控制流转 |
| **Worker** | `src/agents/phase-executor.md` | `"Worker"` | 执行任务、生成证据 |
| **Verifier** | `src/agents/verifier.md` | `"Verifier"` | 独立审计、输出裁决 |
| **Final Verifier** | `src/agents/release-auditor.md` (legacy filename) | `"release_gate"` | 封版外圈门禁（非核心 Agent） |

**Hermes 集成**:
- 使用 `delegate_task()` 调用 Worker/Verifier
- Leader 通过 `.phase_control/` 文件协议与其他 Agent 通信
- 所有 Agent 定义包含 Hermes frontmatter（tools, model, permissionMode）

**Legacy compatibility**: Agent 文件包含 Claude Code frontmatter 作为 legacy compatibility。Hermes 是当前主要集成路径，但不是 TAF 的永久平台边界。

---

## 11. Run Ledger Format (v1.6 新增)

轻量级事件流，记录 orchestrator 和 Agent 执行事件。

**路径**: `.phase_control/run_ledger.jsonl` (运行时生成，不提交仓库)

**格式**: 每行一条 JSON 事件
```json
{"timestamp": "2026-06-02T10:00:00Z", "event": "phase_started", "phase_id": "implement_auth", "attempt": 1}
{"timestamp": "2026-06-02T10:05:00Z", "event": "worker_completed", "phase_id": "implement_auth", "attempt": 1, "exit_code": 0}
{"timestamp": "2026-06-02T10:06:00Z", "event": "verifier_started", "phase_id": "implement_auth", "attempt": 1}
{"timestamp": "2026-06-02T10:08:00Z", "event": "phase_completed", "phase_id": "implement_auth", "verdict": "PASS"}
```

**写入**: 通过 `scripts/hmte-log-event.sh` helper 写入
**读取**: `scripts/hmte-status.sh` 显示最近事件
**用途**: 可观察性、stuck detection、诊断

**v1.7 Parallel Event Types**:
| event | 说明 |
|-------|------|
| `parallel_phase_started` | parallel_safe phase 开始 |
| `worker_shard_delegated` | Worker shard 被委派 |
| `worker_shard_evidence_ready` | Worker shard evidence 到达 |
| `join_verification_result` | Verifier join 验证完成 |
| `parallel_phase_gate_result` | phase_gate join gate 结果 |

---

## 12. Workflow Template Schema (v1.6 新增)

可复用的 workflow 模板，降低 Leader 规划门槛。

**路径**: `src/skills/hmte/templates/workflows.yaml`

**格式**:
```yaml
workflows:
  - name: three-agent-standard
    description: 标准三 Agent 流程
    phases:
      - phase_id: phase_1
        role: Worker
        goal: 执行任务
      - phase_id: phase_2
        role: Verifier
        goal: 验证结果
```

**角色约束**: 只允许 `Leader`/`Worker`/`Verifier` + `release_gate`
**平台**: `platform: hermes-agent` 标记
**使用**: Leader 可参考模板创建 `phases.json`

---

## 附录：文件协议目录结构

```text
.phase_control/
├── phases.json              # Leader 阶段计划
├── state.json               # 当前工作流状态
├── session.json             # 会话元数据
├── goal_lock.json           # P0-1: SHA-256 锁定验收标准
├── lock.json                # P0-5: Leader Jail 激活标记
├── run_ledger.jsonl         # v1.6: 运行时事件流（不提交仓库）
├── instructions/            # {phase}_attempt_{n}_{worker|verifier}.json
├── delegations/             # 委派 receipt (trust_level)
├── logs/                    # {phase}_attempt_{n}.commands.jsonl
├── evidence/                # {phase}_attempt_{n}.json
├── verdicts/                # {phase}_attempt_{n}.json
├── amendments/              # {timestamp}_{phase}_{action}.json
├── errors/                  # 阶段错误信息
├── pids/                    # 后台进程追踪
└── traces/                  # 执行追踪（未来）
```

---

## 13. Review Modes (v1.8)

TriAgentFlow / TAF supports three review modes that adjust Verifier review depth:

### 13.1 Review Mode Types

**standard**
- Normal phase review
- Default mode for most phases
- Verifier applies standard audit checklist

**strict**
- Enhanced review for gate/protocol/schema/security changes
- Requires deeper evidence validation
- Mandatory for changes to phase_gate, protocol scripts, security-sensitive code

**release**
- Final release / public-safe review
- Maximum verification depth
- Applied by Final Verifier (release_gate)
- Includes public-safe checks, terminology consistency, backward compatibility

### 13.2 Important Notes

- Review modes **do not create new Agent roles**
- They are optional instruction-level metadata
- Verifier remains a single Agent type
- Modes adjust review depth, not Agent architecture
- Implementation is instruction-level, not runtime-level

### 13.3 Usage

Review mode can be specified in Verifier instruction:

```json
{
  "phase_id": "security_fix",
  "review_mode": "strict",
  "focus_areas": ["auth changes", "permission checks"]
}
```

For Final Verifier (release_gate), mode is implicitly `release`.

---

## 版本历史

- **v1.7**: Controlled Parallelism — `parallel_safe` execution mode, Worker Shards, Verifier Join Verification, phase_gate 12-item join gate, `--worker-id` for hmte-exec.sh, parallel Run Ledger events
- **v1.6**: 增强 evidence schema（可选字段）、run ledger、workflow 模板
- **v1.5**: Verifier P0-4 强制字段、对抗性测试、receipt 兼容性
- **v1.4**: Leader Jail、Goalpost Lock、Final Check v2
- **v1.2**: 初始发布

---

**文档结束**
