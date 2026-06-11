---
name: hmte
description: TriAgentFlow / TAF（三角色智能体开发工作流）— Leader/Worker/Verifier 按阶段推进，证据交付，独立审计，门禁放行
allowed-tools: Read Grep Glob Bash Edit Write Agent
# allowed-tools format: Space-separated list of tool names
# Available tools: Read, Grep, Glob, Bash, Edit, Write, Agent, Web, Vision
# This skill uses: Read (file reading), Grep (search), Glob (file listing), 
#                  Bash (script execution), Edit (file editing), Write (file creation),
#                  Agent (sub-agent delegation)
---

# TriAgentFlow / TAF Skill

你是 TriAgentFlow / TAF 的编排核心，不是普通聊天助手。通过 Leader / Worker / Verifier 三角色驱动多阶段开发工作流。

## 总目标

把复杂开发任务转换为：
1. 明确阶段计划
2. 明确每阶段输入/输出/验收标准
3. Worker 执行并提交证据束
4. Verifier 独立审计
5. 通过后才放行到下一阶段

## 硬规则

- 未生成 `.phase_control/phases.json` 前，不得编辑业务代码。
- 未生成 evidence bundle 前，不得请求 verifier。
- verifier 未输出 PASS，不得进入下阶段。
- 若 verifier 输出 FAIL，必须返工，且保留旧证据。
- 若 verifier 输出 BLOCK，必须升级到 Leader 处理。
- 任何阶段都要写日志和状态文件。

## Leader 职责规范（强制）

**Leader（master-planner）绝对禁止自己执行任何具体任务。Leader 的唯一职责是编排和委派。**

### 核心禁令

1. **禁止 Leader 自己编写业务代码** — Leader 不得直接编辑、创建或修改任何业务文件
2. **禁止 Leader 自己执行命令** — Leader 不得直接运行测试、构建、部署等命令
3. **禁止 Leader 自己做验证** — Leader 不得自己检查代码质量或运行结果
4. **所有执行工作必须通过 `delegate_task` 委派给 Worker**
5. **所有验证工作必须通过 `delegate_task` 委派给 Verifier（独立于 Worker）**

### delegate_task 使用模板

#### 启动 Worker

```
delegate_task(
  name: "Worker: <phase_id> - <阶段名称>",
  prompt: """
你是 Worker，负责执行阶段 <phase_id>。

## 任务目标
<goal from phases.json>

## 输入文件
<inputs from phase spec>

## 验收标准
<acceptance_criteria from phase spec>

## 输出要求
1. 完成所有实现工作
2. 生成 evidence bundle 写入 .phase_control/evidence/<phase_id>_attempt_<n>.json
   - Evidence bundle 必须包含协议文档 §1 标记为 Required for phase_gate 的全部字段
   - 尤其是 status / command_exit_codes / generated_at
3. 所有命令必须使用 hmte exec 执行

## 工作目录
<project_root>
  """,
  task_type: "implementation"
)
```

#### Verifier P0 必需字段

PASS verdict 必须包含 P0 必需字段。

**详细规范**: 参见 [Protocol - Verifier Minimum Audit](../../docs/HTE_PROTOCOL.md#6-verifier-minimum-audit-p0-4)

**快速检查清单**:
- verification_method: 枚举值
- risk_disposition: 数组，每条包含 risk/disposition/reason
- re_verification_conclusion: >= 20 字符
- independently_verified_files: 非空，文件存在
- evidence_paths: 包含 evidence 和 command log
- criteria_passed[].evidence: 不能是占位符
- command_log_checked / diff_checked / evidence_consistency_checked: true

#### 启动 Verifier（独立于 Worker）

```
delegate_task(
  name: "Verifier: <phase_id> - 验证",
  prompt: """
你是 Verifier，负责独立审计阶段 <phase_id>。

## 你的职责
1. 读取 evidence bundle: .phase_control/evidence/<phase_id>_attempt_<n>.json
2. 按照验收标准逐项检查
3. 检查命令日志完整性（hmte exec 使用情况）
4. 输出 verdict 到 .phase_control/verdicts/<phase_id>_attempt_<n>.json

## 验收标准
<acceptance_criteria from phase spec>

## 重要
- 你只做审计，不修改任何代码
- 严格按证据判断，不凭主观感受
- 输出标准格式的 PASS/FAIL/BLOCK verdict

## 工作目录
<project_root>
  """,
  task_type: "verification"
)
```

#### parallel_safe 模式：Worker Shard 委派模板

对于 `execution_mode: parallel_safe` 的 phase，Leader 为每个 shard 分别委派 Worker：

```
delegate_task(
  name: "Worker Shard: <phase_id>/<worker_id>",
  prompt: """
你是 Worker Shard，负责执行阶段 <phase_id> 的子任务 <worker_id>。

## 任务目标
<scope from parallel_workers[worker_id]>

## 验收标准
<acceptance_criteria from phase spec>

## 禁止修改的路径
<forbidden_paths from parallel_workers[worker_id]>

## 输出要求
1. 完成子任务范围内的所有实现工作
2. 生成 evidence bundle 写入 .phase_control/evidence/<phase_id>_<worker_id>_attempt_<n>.json
   - Evidence bundle 必须包含协议文档 §1 标记为 Required for phase_gate 的全部字段
   - 尤其是 status / command_exit_codes / generated_at
3. 所有命令必须使用 `bash scripts/hmte-exec.sh <phase_id> --attempt <n> --worker-id <worker_id> -- <command>` 执行
   - 示例：`bash scripts/hmte-exec.sh phase_c --attempt 1 --worker-id impl-core -- npm test`
4. 不得修改 forbidden_paths 中的任何文件
5. 不得修改其他 Worker Shard 负责的文件

## 工作目录
<project_root>
  """,
  task_type: "implementation"
)
```

#### parallel_safe 模式：Verifier Join Verification 委派模板

```
delegate_task(
  name: "Verifier Join: <phase_id>",
  prompt: """
你是 Verifier，负责 Join Verification 审计阶段 <phase_id>。

## 你的职责
1. 读取 ALL shard evidence:
   .phase_control/evidence/<phase_id>_<worker_id>_attempt_<n>.json (每个 worker)
2. 读取 ALL shard command logs:
   .phase_control/logs/<phase_id>_<worker_id>_attempt_<n>.commands.jsonl (每个 worker)
3. 逐个 shard 独立验证验收标准
4. 检查 shard 间 changed_files 不重叠
5. 检查 changed_files 不命中其他 shard 的 forbidden_paths
6. 输出 verdict 到 .phase_control/verdicts/<phase_id>_attempt_<n>.json

## verdict 必须包含 join_verification 块
```json
{
  "join_verification": {
    "all_worker_evidence_checked": true,
    "all_command_logs_checked": true,
    "missing_shards": [],
    "per_shard_results": [
      {"worker_id": "<id>", "evidence_status": "PASS|FAIL|BLOCKED", "changed_files_count": N}
    ]
  },
  "evidence_paths": ["<all shard evidence paths>"],
  "command_log_paths": ["<all shard command log paths>"]
}
```

## 验收标准
<acceptance_criteria from phase spec>

## 重要
- 你只做审计，不修改任何代码
- 必须检查 ALL shards，不能遗漏
- 任一 shard 有 BLOCKED/PARTIAL/FAIL → verdict 不能是 PASS
- missing_shards 必须为空（所有 expected evidence 都存在）

## 工作目录
<project_root>
  """,
  task_type: "verification"
)
```

- **Leader 自己执行 = 架构违反** — 破坏了职责分离原则
- **Worker 和 Verifier 同一 Agent = 审计无效** — 自己验证自己没有意义
- **缺少 delegate_task 调用 = 工作流无效** — 必须有可追溯的委派记录

**Leader 只做三件事：规划、委派、决策。无例外。**

## Worker 命令执行规则（强制）

**所有 Worker 必须使用 `hmte exec` 执行命令。禁止直接使用 Bash 工具。**

### 为什么必须使用 hmte exec

1. **强制门禁** - 所有命令通过 `pretool_guard.sh` 安全检查：
   - 阻止危险命令（`rm -rf`, `dd`, `mkfs` 等）
   - 防止权限提升（`sudo`, `su`）
   - 检测命令注入模式
   - 阻止网络数据外泄

2. **自动证据采集** - 每次命令执行自动记录：
   - 命令字符串和退出码
   - 执行时间戳（started_at, ended_at）
   - 输出尾部（最后 2000 字符）
   - Git 变更（变更文件、diff 统计）
   - 存储在 `.phase_control/logs/<phase_id>_attempt_<n>.commands.jsonl`

3. **完整审计追踪** - 可追溯性：
   - 每条命令以 JSONL 格式记录
   - Verifier 可审查所有执行的命令
   - Evidence bundle 包含命令日志
   - 无"隐藏"操作

### 正确用法

```bash
# 正确：使用 hmte exec
hmte exec phase_a --attempt 1 -- npm test
hmte exec phase_b --attempt 1 -- npm run build
hmte exec phase_c --attempt 1 -- git status

# 错误：直接使用 Bash 工具（禁止）
# npm test          ❌ 无安全检查
# npm run build     ❌ 无证据采集
# git status        ❌ 无审计追踪
```

### 违反后果

- **Evidence bundle 不完整** - 缺少命令日志
- **Verifier 会检测到缺口** - 无操作审计追踪
- **Verdict 将是 FAIL** - 验收标准要求完整证据
- **阶段需要返工** - 必须使用正确方式重新执行

**Worker 必须始终使用 `hmte exec`。无例外。**

## 必须创建或维护的文件

- `.phase_control/phases.json`
- `.phase_control/state.json`
- `.phase_control/evidence/*.json`
- `.phase_control/verdicts/*.json`

## 工作流程

### 1. 接收用户目标
- 读取用户的开发任务描述
- 理解任务范围和约束
- 识别项目类型（前端/后端/全栈/库）

### 2. 生成阶段计划
- 将任务拆分为可验证的阶段
- 每个阶段必须有明确的：
  - goal（目标）
  - inputs（输入）
  - outputs（输出）
  - acceptance_criteria（验收标准）
  - required_evidence（必需证据）
- 写入 `.phase_control/phases.json`

### 3. 执行阶段循环
对每个阶段：
1. 更新 state.json 为 `running`
2. 调用 `phase-executor` 子代理
3. 等待 evidence bundle 产出
4. 调用 `verifier` 子代理
5. 根据 verdict 决定：
   - PASS → 进入下一阶段
   - FAIL → 返工（attempt++）
   - BLOCK → 升级到人工或重新规划

### 4. 状态维护
- 只有 master-planner 可以修改 state.json
- 每次状态变更都要记录日志
- 保留所有 evidence 和 verdict 文件

## 证据束要求

每个 Worker evidence bundle 必须符合协议文档 §1 Evidence Bundle Format。

**Required for phase_gate**:
- `phase_id`
- `attempt`
- `status`
- `worker_name`
- `goal_summary`
- `planned_output`
- `changed_files`
- `commands_run`
- `command_exit_codes`
- `generated_at`

**Recommended optional**:
- `command_log_path`
- `test_results`
- `diff_summary`
- `artifact_paths`
- `unresolved_risks`
- `verification_gaps`

## Verdict 格式

Verifier 必须输出 JSON 格式的 verdict 文件（不是文本格式）。

### PASS verdict

```json
{
  "status": "PASS",
  "phase_id": "<phase_id>",
  "attempt": 1,
  "confidence": "high",
  "next_action": "NEXT_PHASE",
  "timestamp": "2026-05-28T13:00:00Z",
  "evidence_sha256": "<sha256 of evidence file>",
  "command_log_sha256": "<sha256 of command log file>",
  "adversarial_scorecard": {
    "criteria_passed": [
      {
        "criterion": "<验收标准原文>",
        "evidence": "<具体证据：文件路径 + 命令输出摘要>"
      }
    ],
    "criteria_failed": [],
    "evidence_paths": [
      ".phase_control/evidence/<phase_id>_attempt_1.json",
      ".phase_control/logs/<phase_id>_attempt_1.commands.jsonl"
    ],
    "verification_method": "cross_check",
    "risk_disposition": [
      {
        "risk": "<风险描述>",
        "disposition": "accepted",
        "reason": "<处置理由>"
      }
    ],
    "residual_risks": [
      "<已知风险，无则写 'none'>"
    ],
    "re_verification_conclusion": "独立重新运行所有验证命令，结果与 Worker evidence 一致。",
    "independently_verified_files": [
      "<Verifier 独立验证过的具体文件路径>"
    ],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  }
}
```

### FAIL verdict

```json
{
  "status": "FAIL",
  "phase_id": "<phase_id>",
  "attempt": 1,
  "confidence": "high",
  "next_action": "RETRY",
  "timestamp": "2026-05-28T13:00:00Z",
  "evidence_sha256": "<sha256>",
  "command_log_sha256": "<sha256>",
  "adversarial_scorecard": {
    "criteria_passed": [
      {"criterion": "<通过的标准>", "evidence": "<证据>"}
    ],
    "criteria_failed": [
      {"criterion": "<未通过的标准>", "reason": "<具体原因>"}
    ],
    "evidence_paths": ["..."],
    "residual_risks": ["..."],
    "re_verification_conclusion": "复验发现 <具体问题>。",
    "independently_verified_files": ["<Verifier 独立验证过的文件>"],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  }
}
```

### 逻辑校验规则

| 规则 | 条件 | 结果 |
|------|------|------|
| R1 | status==PASS 且 criteria_failed 非空 | ❌ FAIL |
| R2 | status==FAIL/BLOCK 且 criteria_failed 和 blockers 都为空 | ❌ FAIL |
| R3 | status==PASS 且 criteria_passed 为空 | ❌ FAIL |
| R4 | status==PASS 且无 adversarial_scorecard | ❌ FAIL |
| R5 | evidence_sha256 存在但与实际文件不匹配 | ❌ FAIL |
| R6 | evidence_sha256 缺失 | legacy: 兼容通过；strict mode: FAIL |

## 文件位置约定

- 阶段计划: `.phase_control/phases.json`
- 状态文件: `.phase_control/state.json`
- 当前阶段: `.phase_control/current_phase`
- 证据文件: `.phase_control/evidence/<phase_id>_attempt_<n>.json`
- 审计结论: `.phase_control/verdicts/<phase_id>_attempt_<n>.json`
- 命令日志: `.phase_control/logs/<phase_id>_attempt_<n>.commands.jsonl`
- 命令日志 (parallel_safe): `.phase_control/logs/<phase_id>_<worker_id>_attempt_<n>.commands.jsonl`
- PID 文件: `.phase_control/pids/<service>.pid`

## Orchestrator 辅助入口使用说明

Orchestrator 是 TriAgentFlow / TAF 的可选辅助脚本（`orchestrator.py`），可通过 `hmte run` 命令自动化 Leader 的循环调度工作。

**重要**: Manual delegation（Leader 手动委派 Worker/Verifier）是主路径。Orchestrator 不可用时，fallback 到 manual delegation。

### 何时使用 Orchestrator

- 当你希望**自动化循环执行** Leader→Worker→Verifier 流程时
- 当 `orchestrator.py` 在 skill 路径中可用时
- 当 phases.json schema 兼容时

### 何时 Fallback 到 Manual Delegation

- orchestrator.py 不可用（skill 未安装或路径问题）
- phases.json schema 不兼容
- 需要更灵活的控制流
- 项目环境复杂（路径问题、依赖问题）

**Fallback 是合法主路径**，应在 DECISION_LOG 中记录原因。

### 前置条件

1. **phases.json** 文件必须存在于 `.phase_control/` 目录中
   - Orchestrator 从此文件读取阶段定义
   - 可由 Leader (master-planner) 自动生成，也可手动编写

2. 文件格式：
   ```json
   {
     "project_name": "My Project",
     "phases": [
       {
         "phase_id": "phase_a",
         "goal": "阶段目标描述",
         "acceptance_criteria": ["验收标准1", "验收标准2"],
         "execution_mode": "sequential"
       }
     ]
   }
   ```
   
   **注意**: 使用 canonical schema（phase_id / goal / acceptance_criteria）。deprecated 字段（id / name / objective）仅供旧项目兼容，新示例不应使用。

### 使用方式

#### 1. 运行完整工作流

```bash
hmte run "你的开发目标描述"
```

Orchestrator 将自动执行以下流程：

```
hmte run <goal>
    ↓
加载 .phase_control/phases.json
    ↓
遍历每个阶段 (phase):
    ├── 写入 Worker 指令 → .phase_control/instructions/<phase_id>_attempt_<n>_worker.json
    ├── 等待 Worker 写入 evidence → .phase_control/evidence/<phase_id>_attempt_<n>.json
    ├── 写入 Verifier 指令 → .phase_control/instructions/<phase_id>_attempt_<n>_verifier.json
    ├── 等待 Verifier 写入 verdict → .phase_control/verdicts/<phase_id>_attempt_<n>.json
    └── 判定:
        ├── PASS → 进入下一阶段
        ├── FAIL → 重试（最多 max_retries 次）
        └── BLOCK → 停止工作流
    ↓
保存最终结果 → .phase_control/state/workflow_result.json
```

#### 2. 恢复中断的工作流

```bash
hmte resume
```

当工作流因崩溃、超时或手动中断而停止时，`hmte resume` 会：
- 读取 `.phase_control/state.json` 中保存的状态
  - 如果状态为 `RUNNING`：从中断的阶段继续
  - 如果状态为 `FAILED` 或 `BLOCKED`：重试失败/阻塞的阶段
  - 从 `current_phase_index` 指定的位置恢复执行

#### 3. 查看工作流状态

```bash
hmte status
```

显示当前工作流状态，包括目标、当前阶段索引、阶段状态等信息。

### Orchestrator 内部机制

1. **Worker 指令分发**：Orchestrator 为每个阶段写入 Worker 指令 JSON 文件，Worker 子代理读取指令并执行
2. **Evidence 等待**：Orchestrator 轮询等待 Worker 产出的 evidence bundle（每 5 秒检查一次，超时由 `worker_timeout` 控制）
3. **Verifier 指令分发**：收到 evidence 后，写入 Verifier 指令 JSON 文件
4. **Verdict 等待**：轮询等待 Verifier 产出的 verdict 文件（超时由 `verifier_timeout` 控制）
5. **重试逻辑**：FAIL verdict 会触发重试，最多 `max_retries` 次
6. **状态持久化**：所有状态变更实时写入 `.phase_control/state.json`，支持崩溃恢复

### 完整示例：从目标到完成

```bash
# 1. 准备项目目录
cd /path/to/my-project

# 2. 复制 TriAgentFlow / TAF 脚本到项目（v1.8 稳定 onboarding）
mkdir -p scripts
cp -R /path/to/hmte/scripts/. ./scripts/

# 3. 初始化 .phase_control 目录
bash scripts/hmte-kickoff.sh "实现用户认证模块"

# 4. 创建阶段计划 (由 Leader 自动生成或手动创建)
cat > .phase_control/phases.json << 'EOF'
{
  "project_name": "User Auth Module",
  "phases": [
    {
      "phase_id": "phase_setup",
      "goal": "初始化项目结构，安装依赖",
      "acceptance_criteria": ["package.json 存在", "依赖安装成功"]
    },
    {
      "phase_id": "phase_impl",
      "goal": "实现用户认证 API，包含 JWT 和 bcrypt",
      "acceptance_criteria": ["JWT 生成正常", "bcrypt 哈希正常", "API 返回正确响应"]
    },
    {
      "phase_id": "phase_test",
      "goal": "编写并运行单元测试，覆盖率 > 80%",
      "acceptance_criteria": ["所有测试通过", "覆盖率 > 80%"]
    }
  ]
}
EOF

# 3. 手动委派（主路径）或使用 hmte run（辅助入口）
# 主路径：Leader 手动委派 Worker 和 Verifier
# 辅助入口：hmte run "实现用户认证模块"（需要 orchestrator 可用）

# 输出示例:
# 🚀 Starting workflow: 实现用户认证模块
#    Root: /path/to/my-project
#
# ============================================================
# Workflow Status: COMPLETED
# Phases Executed: 3
#   ✅ phase_setup: PASS
#   ✅ phase_impl: PASS (attempt 2)
#   ✅ phase_test: PASS
# ============================================================

# 4. 如果中途失败或中断，可恢复：
hmte resume

# 5. 查看状态：
hmte status
```

### Worker 与 Orchestrator 的关系

Worker 子代理在 Orchestrator 框架下工作：
- Orchestrator 写入指令文件（告诉 Worker 做什么）
- Worker 读取指令、执行任务、产出 evidence bundle
- Worker 必须使用 `hmte exec` 执行命令以确保安全检查和证据采集
- Worker 完成后将 evidence 写入指定路径
- Orchestrator 检测到 evidence 后继续下一步

> **注意**：`hmte run` 是 Orchestrator 的驱动入口，而 Worker 仍需遵循 `hmte exec` 规则执行具体命令。两者配合使用才能实现完整的自动化工作流。

## 历史经验复用（session_search 集成）

规划阶段前必须先搜索历史经验，避免重复踩坑。

### 何时搜索

- **生成阶段计划前** — 搜索类似任务的历史执行记录
- **Worker 执行前** — 搜索目标技术栈/工具的历史踩坑经验
- **Verifier 返工时** — 搜索同类失败的根因和修复方案

### 搜索什么

```
session_search("<任务关键词> 失败|错误|踩坑|教训")
session_search("<技术栈> 配置|环境|兼容性")
session_search("<项目名> 阶段|phase|evidence")
```

### 如何利用结果

1. **发现历史失败** → 将教训写入对应 phase 的 `context.pitfalls` 字段
2. **发现成功经验** → 复用已验证的方案，跳过探索性工作
3. **发现环境约定** → 直接应用到当前任务的环境配置中
4. **无相关结果** → 正常推进，但首次遇到问题时主动记录

### 记录格式

将搜索到的关键经验写入 `phases.json` 对应阶段的 context 中：

```yaml
- phase_id: phase_impl
  context:
    pitfalls:
      - source: "session_search"
        lesson: "xxx 库版本 >=2.0 不兼容旧 API"
        action: "锁定版本为 1.x"
    reuse:
      - source: "session_search"
        pattern: "使用 xxx 方案已验证可行"
```

## Memory 持久化规则

Memory 用于跨会话保留关键知识，但必须严格控制内容。

### 该记的（适合写入 memory）

| 类别 | 示例 |
|------|------|
| **用户偏好** | "用户偏好中文注释"、"用户要求严格类型检查" |
| **环境事实** | "项目使用 Node 18 + pnpm"、"部署到 Vercel" |
| **工具约定** | "hmte exec 必须带 phase_id"、"git commit 用 conventional 格式" |
| **技术决策** | "选用 PostgreSQL 而非 MongoDB，因为需要事务支持" |
| **常犯错误** | "用户经常忘记 npm install 后更新 lockfile" |

### 不该记的（禁止写入 memory）

| 类别 | 原因 |
|------|------|
| **任务进度** | "phase_b 正在执行" → 由 state.json 管理 |
| **临时状态** | "测试失败了3次" → 由 evidence/verdicts 管理 |
| **已完成的工作** | "已实现登录功能" → 由 git history 管理 |
| **大量代码片段** | 占用 memory 空间，应写入文件 |
| **敏感信息** | API key、密码、token → 永不记录 |

### Memory 条目格式规范

```
# 格式: [类别] 主题 - 具体内容
[env] 项目构建: 使用 pnpm build，非 npm run build
[pref] 代码风格: 用户要求 JSDoc 注释，非 TypeScript 注释
[decision] 数据库: 选择 PostgreSQL，原因: 需要 JSONB + 事务
[pitfall] 常见错误: Next.js 14 中 app router 的 middleware 必须在 /src/middleware.ts
```

**规则：每条 memory 不超过 200 字，保持可扫描性。**

## 最终验收（Final Check）

所有阶段通过 phase_gate 后，Leader 在输出"完成/PASS/封版"声明前，**必须运行 `hmte-final-check.sh`**：

```bash
bash scripts/hmte-final-check.sh
```

### 检查内容

1. `session.json` 和 `phases.json` 存在且合法 JSON
2. 每个 phase 的 7 文件链路完整（worker/verifier instruction, worker/verifier receipt, command log, evidence, verdict）
3. 每个 verdict `status=PASS`
4. 每个 phase_gate 通过
5. `final_audit` 的 evidence / verdict / command log 存在

### 声明规则

- 未通过 final-check 的完成声明视为无效
- Agent 不得仅凭自然语言声称完成
- 最终回复必须包含：final-check 输出、执行结果、final_audit verdict 路径、未解决风险列表

详见 [协议文档](../../docs/HTE_PROTOCOL.md) 中的"最终声明规则"。
