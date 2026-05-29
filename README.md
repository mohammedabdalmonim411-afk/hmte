# HTE — Hermes Team Engine

> 面向 Hermes Agent 的多 Agent 协作开发框架。

HTE 将 AI 辅助开发从"单个模型独立完成所有事情"，升级为"多 Agent 分工协作、阶段推进、证据交付、独立审计、门禁放行"的工程化工作流。

它围绕 Leader / Worker / Verifier 三类角色组织任务：

- **Leader**：拆解目标、规划阶段、维护流程状态、控制阶段流转。
- **Worker**：执行明确范围内的实现任务，并产出证据材料。
- **Verifier**：基于证据进行独立审计，输出 PASS / FAIL / BLOCK 裁决。
- **phase_gate**：检查当前阶段是否满足放行条件。
- **orchestrator**：管理基于文件协议的阶段流转。

![状态](https://img.shields.io/badge/版本-v1.2.0-green)
![定位](https://img.shields.io/badge/定位-多%20Agent%20协作框架-blue)
![机制](https://img.shields.io/badge/机制-阶段门禁%20/%20证据链-purple)

> 当前状态：Beta
> 当前重点：统一文件协议、命令日志、阶段门禁、独立审计和核心流程测试。

## 核心理念

HTE 的目标不是让一个模型包办所有事情，而是让多个 AI Agent 像工程团队一样协同工作。

复杂任务应当被拆分为清晰阶段，每个阶段都有明确目标、输入、输出、执行记录、证据材料和审计结果。
Leader 负责组织，Worker 负责执行，Verifier 负责审查，phase_gate 负责放行。

通过这种方式，AI 协作过程可以被检查、复盘、打回和持续改进。

## 设计哲学

HTE 基于一个简单判断：复杂 AI 开发不适合由单个模型同时承担规划、实现、验证和放行。

更合理的方式是让不同 Agent 承担不同职责：

- 规划者专注目标拆解和阶段控制；
- 执行者专注具体实现；
- 审计者专注证据检查和质量判断；
- 门禁机制负责阶段是否可以继续。

HTE 将这些角色连接成一个阶段化工作流，使 AI 协作不只停留在提示词层面，而是沉淀为可运行、可检查、可复盘的工程流程。

## 架构概览

```text
用户目标
  ↓
Leader
  - 分析需求
  - 创建 .phase_control/phases.json
  - 拆分阶段
  - 管理流程状态
  ↓
Instruction Files
  - .phase_control/instructions/
  - 为 Worker / Verifier 提供明确任务说明
  ↓
Worker
  - 执行阶段任务
  - 通过 hmte exec 运行命令
  - 产出 command log 和 evidence bundle
  ↓
Verifier
  - 独立审计 evidence
  - 输出 JSON verdict
  ↓
phase_gate
  - 检查证据、日志、裁决和阶段一致性
  - 决定当前阶段是否放行
  ↓
orchestrator
  - 管理文件协议工作流
  - 根据 phase_gate 结果继续、打回或阻断
```

## 核心角色

| 角色 | 主要职责 | 产物 |
|------|---------|------|
| Leader | 阶段规划、任务拆分、状态管理、阶段流转 | phases.json、instruction files、state |
| Worker | 执行阶段任务、运行命令、提交实现和证据 | command logs、evidence bundle |
| Verifier | 独立审计证据、检查验收标准、输出裁决 | verdict JSON |
| phase_gate | 检查阶段是否满足放行条件 | PASS / FAIL / BLOCK |
| orchestrator | 管理文件协议流程 | 阶段流转结果 |

## 工作流保障机制

HTE 使用项目本地的 `.phase_control/` 目录记录阶段化协作过程。

每个阶段都围绕一组可检查文件推进：

- instruction files：阶段任务说明；
- command logs：Worker 执行命令的记录；
- evidence bundles：阶段交付证据；
- verdicts：Verifier 审计裁决；
- phase gate results：阶段放行结果。

这些文件共同构成阶段交付记录，使 Leader、Verifier 和用户能够检查：

- 当前阶段做了什么；
- 由谁执行；
- 执行了哪些命令；
- 产生了哪些证据；
- 为什么 PASS、FAIL 或 BLOCK；
- 下一步应该继续、返工还是升级处理。

## 文件协议

HTE 使用项目本地 `.phase_control/` 目录保存工作流状态和阶段产物。

```text
.phase_control/
├── phases.json
├── state.json
├── instructions/
├── delegations/
├── evidence/
├── verdicts/
├── logs/
├── errors/
├── pids/
└── traces/
```

| 路径 | 作用 |
|------|------|
| `.phase_control/phases.json` | Leader 创建的阶段计划 |
| `.phase_control/state.json` | 当前工作流状态 |
| `.phase_control/instructions/` | Worker / Verifier 的任务说明 |
| `.phase_control/delegations/` | 委派意图记录 |
| `.phase_control/logs/{phase}_attempt_{n}.commands.jsonl` | hmte exec 生成的命令日志 |
| `.phase_control/evidence/{phase}_attempt_{n}.json` | Worker 提交的阶段证据 |
| `.phase_control/verdicts/{phase}_attempt_{n}.json` | Verifier 输出的阶段裁决 |
| `.phase_control/errors/` | 阶段错误与阻断信息 |

## 命令日志

Worker 应通过 `hmte exec` 执行阶段命令。

```bash
bash scripts/hmte-exec.sh phase_a --attempt 1 -- npm test
```

命令执行后会生成：

```text
.phase_control/logs/phase_a_attempt_1.commands.jsonl
```

每一行都是一条 JSON 记录：

```json
{
  "phase_id": "phase_a",
  "attempt": 1,
  "command": "npm test",
  "exit_code": 0,
  "runner": "hmte exec",
  "started_at": "2026-05-28T13:00:00Z",
  "ended_at": "2026-05-28T13:00:02Z",
  "output_tail": "..."
}
```

这些日志用于阶段审计、错误排查和 phase_gate 判断。

## Evidence Bundle

Worker 在每个阶段结束时提交 evidence bundle：

```json
{
  "phase_id": "phase_a",
  "attempt": 1,
  "worker_name": "phase-executor",
  "goal_summary": "实现登录接口",
  "changed_files": ["src/api/auth.js", "tests/auth.test.js"],
  "command_log_path": ".phase_control/logs/phase_a_attempt_1.commands.jsonl",
  "commands_run": ["npm test"],
  "command_exit_codes": [0],
  "test_results": {"total": 12, "passed": 12, "failed": 0},
  "unresolved_risks": ["生产环境 JWT secret 需要单独配置"],
  "verification_gaps": [],
  "generated_at": "2026-05-28T13:03:00Z"
}
```

## Verdict Format

Verifier 输出 JSON verdict：

```text
.phase_control/verdicts/{phase_id}_attempt_{n}.json
```

示例：

```json
{
  "status": "PASS",
  "phase_id": "phase_a",
  "attempt": 1,
  "timestamp": "2026-05-28T13:05:00Z",
  "evidence_sha256": "64-character-sha256",
  "command_log_sha256": "64-character-sha256",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "单元测试通过", "evidence": ".phase_control/logs/phase_a_attempt_1.commands.jsonl"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_a_attempt_1.json"],
    "residual_risks": ["生产配置需要部署时单独确认"],
    "re_verification_conclusion": "证据支持 PASS"
  }
}
```

| 状态 | 含义 |
|------|------|
| PASS | 当前阶段满足放行条件 |
| FAIL | 当前阶段需要返工 |
| BLOCK | 当前阶段缺少必要条件，需要升级处理 |

## Phase Gate

`phase_gate` 负责判断当前阶段是否可以继续。

```bash
bash src/skills/hmte/scripts/phase_gate.sh phase_a --attempt 1
```

它会检查：

- phase ID 和 attempt 是否一致；
- command log 是否存在并可解析；
- evidence bundle 是否存在；
- verdict JSON 是否存在；
- verdict status 是否有效；
- 当前阶段是否满足放行条件。

只有 phase_gate 通过后，orchestrator 才能继续推进后续阶段。

## Quick Start

### 1. 克隆项目

```bash
git clone https://github.com/mohammedabdalmonim411-afk/hmte.git
cd hmte
```

### 2. 安装 Hermes Skill

```bash
bash install-to-hermes.sh
```

### 3. 将运行时结构复制到目标项目

```bash
cp -r scripts .phase_control /path/to/your/project/
cd /path/to/your/project
```

### 4. 启动工作流

```bash
bash scripts/hmte-start.sh
```

在 Hermes 中输入：

```text
请使用 HTE 工作流处理这个任务。先作为 Leader 创建 phases.json，再按阶段委派 Worker 和 Verifier。Leader 不直接执行 Worker 的实现任务。
```

### 5. 执行阶段命令

```bash
bash scripts/hmte-exec.sh phase_a --attempt 1 -- npm test
```

### 6. 检查阶段门禁

```bash
python3 src/skills/hmte/scripts/hmte-audit-flow.py phase_a 1 --json
bash src/skills/hmte/scripts/phase_gate.sh phase_a --attempt 1
```

### 7. 运行测试

```bash
bash scripts/e2e-core-workflow-test.sh
bash scripts/e2e-anti-fake-test.sh
```

## 当前限制

HTE 当前处于 Beta 阶段。

当前版本需要注意：

- `hmte run` 当前是基于文件协议的工作流状态机；
- Worker / Verifier 的实际调用依赖 Hermes 侧的 `delegate_task` 或外部集成；
- delegation receipt 当前用于记录委派意图；
- OBSERVED 级别的委派证明需要未来接入 Hermes tool-call 日志；
- Shell 脚本主要面向 Unix / Linux / macOS 环境；
- Claude Code 相关文件保留为 legacy compatibility。

## Testing

### 语法检查

```bash
python3 -m py_compile src/skills/hmte/scripts/hmte-audit-flow.py
python3 -m py_compile src/skills/hmte/scripts/orchestrator.py
bash -n src/skills/hmte/scripts/phase_gate.sh
bash -n scripts/hmte-exec.sh
```

### 核心工作流测试

```bash
bash scripts/e2e-core-workflow-test.sh
```

### 工作流保障测试

```bash
bash scripts/e2e-anti-fake-test.sh
```

### Legacy 测试

```bash
bash scripts/hmte-e2e-legacy.sh
```

## Roadmap

### v0.4 — 核心流程接入

- [x] command log 协议统一
- [x] phase_gate 接入主流程
- [x] audit-flow 校验
- [x] core workflow E2E

### v1.2 — GitHub 发布

- [ ] README 重写
- [ ] HERMES.md 同步
- [ ] 文档旧口径清理
- [ ] tar.gz 审计包
- [ ] GitHub Actions 校验

### v0.6 — 委派记录增强

- [ ] 接入 Hermes tool-call 日志
- [ ] 区分 INTENT_ONLY 与 OBSERVED
- [ ] 为关键阶段提供更强的委派确认能力

### Future

- [ ] Dashboard
- [ ] Parallel phases
- [ ] Windows support
- [ ] CI/CD templates

---

完整代码和文档请参考项目仓库。
