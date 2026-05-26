# Mavis-like Team Engine 实施计划

## 项目概述

在 Claude Code 中实现一个通用的多代理开发系统，复刻 Leader/Worker/Verifier 架构。

## 核心目标

构建一个可在 Claude Code 内运行的通用开发流程系统：
- **主代理（master-planner）**：规划、拆阶段、维护状态机、派发任务、决定放行
- **子代理（phase-executor）**：执行单阶段工作并产出证据束
- **子代理（verifier）**：独立审计结果，专门找错，输出 PASS/FAIL/BLOCK

## 架构原则

1. **先建立 harness，再做功能**
2. **先创建文件结构与状态机，再写角色提示词**
3. **任何阶段在 verifier 输出 PASS 前，不得推进**
4. **所有结论必须有 evidence bundle 支撑**
5. **优先使用 Claude Code 原生能力**：skills、subagents、hooks、worktree、goal

## 实施路径

### A. Skill-only 路径（优先）
- 只依赖 Claude Code 原生 skills + subagents + hooks + worktree
- 适合无浏览器自动化或先做流程验证
- verifier 基于测试、diff、日志、构建结果、静态检查做判定

### B. MCP-assisted 路径（可选）
- 在 Skill-only 基础上，为 phase-executor/verifier 注入浏览器能力
- 优先支持 Playwright MCP
- 可选支持 Chrome DevTools MCP

## 目录结构

```
mavis-team-engine/
├── README.md
├── CLAUDE.md
├── .claude/
│   ├── skills/
│   │   └── mavis-team-engine/
│   │       ├── SKILL.md
│   │       ├── phase-template.md
│   │       ├── evidence-schema.json
│   │       ├── audit-checklist.md
│   │       └── scripts/
│   │           ├── phase_gate.sh
│   │           ├── write_state.py
│   │           └── collect_evidence.sh
│   ├── agents/
│   │   ├── master-planner.md
│   │   ├── phase-executor.md
│   │   └── verifier.md
│   ├── hooks/
│   │   ├── pretool_guard.sh
│   │   ├── stop_gate.sh
│   │   └── task_naming.sh
│   └── settings.json
├── .phase_control/
│   ├── phases.yaml
│   ├── state.json
│   ├── current_phase
│   ├── run.lock
│   ├── evidence/
│   ├── verdicts/
│   ├── logs/
│   ├── pids/
│   └── traces/
└── scripts/
    ├── mavis-start.sh
    ├── mavis-stop.sh
    ├── mavis-status.sh
    └── mavis-e2e.sh
```

## 状态机设计

### state.json 结构
```json
{
  "session_id": "uuid",
  "project_root": "/path/to/project",
  "mode": "skill-only",
  "goal": "用户目标描述",
  "current_phase": "phase_id",
  "phase_status": "pending|running|evidence_ready|verifying|passed|failed|blocked",
  "retries_used": 0,
  "max_retries": 2,
  "started_at": "2026-05-26T00:00:00Z",
  "updated_at": "2026-05-26T00:00:00Z",
  "active_worker": "agent_id",
  "active_verifier": "agent_id",
  "evidence_paths": [],
  "verdict_path": "",
  "next_action": "CONTINUE|REWORK|ESCALATE|RELEASE"
}
```

### phases.yaml 结构
```yaml
phases:
  - id: phase_a
    name: "仓库与需求梳理"
    objective: "理解项目结构和需求"
    inputs: ["用户需求", "项目代码"]
    outputs: ["需求文档", "项目结构分析"]
    acceptance_criteria:
      - "需求明确无歧义"
      - "项目结构清晰"
    required_evidence:
      - "changed_files"
      - "commands_run"
    timeout_soft: 600
    timeout_hard: 1200
    max_retries: 2
    escalation_rule: "连续2次FAIL升级"
```

## 角色定义

### 1. master-planner
- **职责**：读取用户目标 → 生成 phases.yaml → 调用 phase-executor 和 verifier → 维护状态机
- **模型**：opus（环境受限则 sonnet）
- **权限**：唯一可修改 state.json 和 current_phase
- **工具**：Agent tool 调用子代理

### 2. phase-executor
- **职责**：执行当前 phase → 产出 evidence bundle → 提交待审计
- **模型**：sonnet
- **隔离**：worktree 隔离
- **输出**：evidence bundle JSON
- **禁止**：自称"最终通过"

### 3. verifier
- **职责**：审计 evidence bundle → 输出 PASS/FAIL/BLOCK verdict
- **模型**：opus（预算紧张可 sonnet）
- **权限**：默认只读，不编辑业务代码
- **依据**：evidence bundle、测试结果、diff、日志
- **输出**：固定 verdict 格式

## Evidence Bundle Schema

```json
{
  "phase_id": "phase_a",
  "attempt": 1,
  "worker_name": "phase-executor",
  "goal_summary": "理解项目结构",
  "planned_output": "项目结构文档",
  "changed_files": ["README.md", "docs/structure.md"],
  "commands_run": ["ls -la", "tree -L 2"],
  "command_exit_codes": [0, 0],
  "tests_run": [],
  "test_results": [],
  "lint_results": [],
  "build_results": [],
  "screenshots": [],
  "traces": [],
  "console_errors": [],
  "network_findings": [],
  "diff_summary": "Added project structure documentation",
  "artifact_paths": ["docs/structure.md"],
  "unresolved_risks": [],
  "verification_gaps": [],
  "generated_at": "2026-05-26T00:00:00Z"
}
```

## Verdict 格式

### PASS
```
VERDICT: PASS
PHASE_ID: phase_a
CONFIDENCE: high
ACCEPTANCE_CHECKS:
- [x] 需求明确无歧义
- [x] 项目结构清晰
RESIDUAL_RISKS:
- 无
EVIDENCE_USED:
- .phase_control/evidence/phase_a_attempt_1.json
NEXT_ACTION: RELEASE_TO_NEXT_PHASE
```

### FAIL
```
VERDICT: FAIL
PHASE_ID: phase_a
CONFIDENCE: high
FAILED_CHECKS:
- [ ] 需求明确无歧义
ROOT_CAUSES:
- 需求文档缺少关键字段定义
REQUIRED_REWORK:
- 补充字段定义
- 添加示例
EVIDENCE_USED:
- .phase_control/evidence/phase_a_attempt_1.json
NEXT_ACTION: RETURN_TO_EXECUTOR
```

### BLOCK
```
VERDICT: BLOCK
PHASE_ID: phase_a
CONFIDENCE: high
BLOCKERS:
- 缺少必要的依赖文件
MISSING_INPUTS:
- package.json
SAFE_OPTIONS:
- 创建默认 package.json
- 询问用户提供
EVIDENCE_USED:
- .phase_control/evidence/phase_a_attempt_1.json
NEXT_ACTION: ESCALATE_TO_LEADER
```

## 超时与重试策略

- **soft timeout**：10 分钟（警告）
- **hard timeout**：20 分钟（强制终止）
- **max_retries**：2 次
- **连续 2 次 FAIL**：升级到 Leader 重规划
- **任意 BLOCK**：立刻停止并升级
- **缺证据**：不允许 PASS，必须 FAIL 或 BLOCK

## Hooks 设计

### 1. pretool_guard.sh
- 阻断危险命令（rm -rf /、格式化等）
- 限制命令必须在项目目录内运行

### 2. stop_gate.sh
- 检查是否还有未完成的 phase
- 检查是否还有未产出的 verdict
- 检查是否还有后台服务未清理
- 未完成则阻止停止

### 3. task_naming.sh
- 确保任务命名与 phase_id 一致
- 防止模糊 task subject

## 日志与 PID 约定

### PID 文件
- `.phase_control/pids/frontend.pid`
- `.phase_control/pids/backend.pid`
- `.phase_control/pids/<phase_id>-worker.pid`
- `.phase_control/pids/<phase_id>-verifier.pid`

### 日志文件（JSONL）
- `.phase_control/logs/leader.jsonl`
- `.phase_control/logs/<phase_id>-worker.jsonl`
- `.phase_control/logs/<phase_id>-verifier.jsonl`

每行包含：
```json
{
  "ts": "2026-05-26T00:00:00Z",
  "role": "worker",
  "phase_id": "phase_a",
  "event": "start",
  "status": "running",
  "summary": "开始执行 phase_a",
  "evidence_path": "",
  "verdict_path": "",
  "model": "sonnet",
  "attempt": 1
}
```

## 样例 Phase Flow

### Phase A: 仓库与需求梳理
- **输入**：用户需求、项目代码
- **输出**：需求文档、项目结构分析
- **验收标准**：需求明确、结构清晰
- **证据要求**：changed_files、commands_run
- **失败策略**：补充文档、重新分析

### Phase B: 架构/计划确认
- **输入**：需求文档、项目结构
- **输出**：架构设计、实施计划
- **验收标准**：架构合理、计划可行
- **证据要求**：设计文档、计划文档
- **失败策略**：调整架构、细化计划

### Phase C: 实现
- **输入**：架构设计、实施计划
- **输出**：代码实现、单元测试
- **验收标准**：代码正确、测试通过
- **证据要求**：changed_files、test_results、build_results
- **失败策略**：修复 bug、补充测试

### Phase D: 测试与浏览器验证
- **输入**：代码实现
- **输出**：测试报告、截图证据
- **验收标准**：所有测试通过、UI 正常
- **证据要求**：test_results、screenshots、console_errors
- **失败策略**：修复失败测试、调整 UI

### Phase E: 最终审计与交付
- **输入**：完整实现
- **输出**：交付清单、文档
- **验收标准**：功能完整、文档齐全
- **证据要求**：所有 phase 的 evidence
- **失败策略**：补充缺失项

## 实施步骤

### 第一轮（当前）：骨架搭建
1. ✅ 创建项目目录
2. ⏳ 创建目录结构
3. ⏳ 编写状态机文件（phases.yaml、state.json）
4. ⏳ 编写角色定义文件（master-planner.md、phase-executor.md、verifier.md）
5. ⏳ 编写 SKILL.md
6. ⏳ 编写基础脚本（phase_gate.sh、write_state.py）

### 第二轮：核心功能
1. 实现 master-planner 逻辑
2. 实现 phase-executor 逻辑
3. 实现 verifier 逻辑
4. 实现状态机转换
5. 实现 evidence 收集

### 第三轮：Hooks 与工具
1. 实现 pretool_guard.sh
2. 实现 stop_gate.sh
3. 实现 task_naming.sh
4. 实现 mavis-start.sh、mavis-stop.sh、mavis-status.sh

### 第四轮：测试与验证
1. 编写 E2E 测试脚本
2. 运行最小示例验证
3. 修复发现的问题
4. 完善文档

## MCP 集成（可选）

### Playwright MCP
```bash
claude mcp add playwright npx @playwright/mcp@latest
```

### Chrome DevTools MCP
```bash
claude mcp add chrome-devtools --scope user npx chrome-devtools-mcp@latest
```

## 验收清单

- [ ] 目录结构完整
- [ ] SKILL.md 可被 Claude Code 识别
- [ ] subagents frontmatter 合法
- [ ] verifier 无写主代码权限
- [ ] state.json 可正确反映阶段状态
- [ ] evidence/verdict 文件能一一对应
- [ ] 至少一个 FAIL -> REWORK -> PASS 的演示跑通
- [ ] 若启用 MCP，至少一种浏览器证据可采集
- [ ] README 或文档说明清晰
- [ ] 所有脚本具备基本错误处理

## 模型策略

- **master-planner**：默认 opus，复杂规划优先 opus
- **phase-executor**：默认 sonnet
- **verifier**：默认 opus；预算紧张时可用 sonnet
- **摘要器**（可选）：haiku 用于日志压缩、状态摘要

## 下一步

立即开始创建目录结构和核心文件。
