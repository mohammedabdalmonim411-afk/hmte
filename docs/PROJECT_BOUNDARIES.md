# TriAgentFlow / TAF Project Boundaries and Design Principles

**Version**: 2.0  
**Status**: Authoritative Reference  
**Purpose**: 明确项目边界，让未来贡献者和 AI Agent 理解 TriAgentFlow / TAF 的约束与设计哲学

*Formerly HTE / Hermes Team Engine. The `hmte` command prefix is retained as a legacy compatibility prefix.*

---

## Core Identity

**TriAgentFlow / TAF is a three-agent development workflow for AI-assisted engineering.**

TriAgentFlow / TAF 不是代码测试框架，不是 CI/CD 平台，不是 Agent 协作平台。

TriAgentFlow / TAF 专注做一件事：**让三角色 Agent 协作过程可验证、可审计、可复盘**。

---

## Five Constitutional Constraints

以下五条是 TriAgentFlow / TAF 项目的顶层宪法，任何规划、建议、设计都必须服从这五条：

### 1. Three-Agent Pattern (Leader / Worker / Verifier)

**原则**: Leader / Worker / Verifier 是项目骨架，不得新增核心角色。

**允许**:
- Worker Shards — Worker 的受控并行扩展（v1.7 Controlled Parallelism）
- Optional schema fields — 向后兼容的可选字段扩展
- Lightweight files and scripts — 轻量文件和脚本

**禁止**:
- ❌ Coordinator / Aggregator / Manager
- ❌ JoinVerifier / ReviewAgent / ApprovalAgent
- ❌ Scheduler / Dispatcher / Orchestrator Agent（orchestrator 是脚本，不是 Agent）

**Final Verifier 说明**:
- Final Verifier 是 **release_gate / 封版外圈门禁**，不是第四核心 Agent
- 职责：hmte-final-check.sh / hmte-lint-protocol.sh (release) / public-safe scan / VALIDATION_SUMMARY.md
- 不替代 Verifier，不是 JoinVerifier

---

### 2. Gate Decides (not natural language claims)

**原则**: phase_gate / final-check 高于自然语言声明。

**允许**:
- Agent 自称完成、PASS、封版
- 但必须由文件协议和门禁脚本放行

**禁止**:
- ❌ 用总结报告替代证据链
- ❌ 用自评摘要替代 verdict
- ❌ 用口头说明替代 evidence

**实践**:
- Protocol Eval Harness 验证门禁是否真的生效
- Gate Negative Test 制度强制门禁变更有坏样例
- Validation Map 明确"改什么必须验证什么"

---

### 3. Evidence First (not summaries)

**原则**: evidence、verdict、receipt、command log 必须闭环。

**允许**:
- 新增可选字段（如 v1.8 的 review_findings）
- 扩展 schema（保持向后兼容）

**禁止**:
- ❌ 用自然语言摘要替代结构化证据
- ❌ 用对话历史替代文件化产物
- ❌ 用 Agent 记忆替代文件协议

**实践**:
- Planning Protocol 输出文件化规划
- Verifier Findings 输出结构化审计结果
- Validation Map 明确每种改动需要的证据

---

### 4. Generic Protocol (not code-specific)

**原则**: TriAgentFlow / TAF 是通用工程协作治理协议，不绑定特定开发工具链。

**允许**:
- 提供代码开发场景示例
- 借鉴其他方法论的治理抽象

**禁止**:
- ❌ 把 TriAgentFlow / TAF 写成只适合 Python / Node / shell 的工具
- ❌ 把 validation 等同于 unit test
- ❌ 把 TriAgentFlow / TAF 绑定到 GitHub PR / CI/CD

**实践**:
- Validation Map 覆盖多种验证类型（测试、lint、构建、文档一致性、人工审计）
- 示例覆盖代码、文档、配置、AI Skill、release 流程
- 术语使用 validation / review / evidence / phase / risk，而非 test / PR / build / deploy

**适用场景**:
- 代码开发：feature 实现、bug 修复、重构
- 文档工作：技术文档、API 文档、用户手册
- 配置变更：基础设施配置、部署配置
- AI Skill 开发：Skill 编写、测试、封版
- Release 流程：版本封版、审计、发布检查

---

### 5. Lightweight Mechanism (not platforms)

**原则**: 优先选择轻量、文件化、可审计、可维护的方案。

**允许**:
- 轻量 Markdown 协议文件
- 最小 shell/Python 评测脚本
- 文件化规划和决策记录

**禁止**:
- ❌ Runtime / Daemon / SQLite / Dashboard / Web UI
- ❌ DAG / dependencies / 拓扑排序
- ❌ GraphRAG / AST 索引服务 / Docker Sandbox
- ❌ IDE Timeline / 后台服务
- ❌ Agent 协作平台（Hermes 已是）
- ❌ CI/CD 平台
- ❌ Skill 超市

**实践**:
- Protocol Eval Harness: 轻量 shell 脚本 + 7 cases (E001-E003 MVP baseline + E004-E007 P0 fail-closed regression)
- Planning Protocol: Markdown 文件
- Validation Map: Markdown 文档
- Complexity Budget: 文档约束，不是自动化工具
- 所有协议产物都是人类可读文本

**v1.8 预算控制**:
- 新增核心文档：7 个
- 新增脚本：3 个 (hmte-validate-phases.sh, hmte-eval.sh, phase_gate.sh wrapper)
- 新增依赖：0 个
- Eval cases：7 个（E001-E003 MVP + E004-E007 P0 fail-closed regression cases）

---

## How to Evaluate New Proposals

当评估新功能、新模块、新能力时，按以下顺序检查：

1. **Does it add a new core Agent?**  
   → ❌ Reject（违反宪法 1）

2. **Does it require runtime / daemon / DB / dashboard?**  
   → ❌ Reject（违反宪法 5）

3. **Does it bind to specific language / tool / platform?**  
   → ❌ Reject（违反宪法 4）

4. **Does it bypass gate / evidence / protocol?**  
   → ❌ Reject（违反宪法 2 和 3）

5. **Can it be done with files + scripts?**  
   → ✅ Consider（符合宪法 5）

6. **Does it serve generic governance?**  
   → ✅ Consider（符合宪法 4）

7. **Does it keep v1.7 compatibility?**  
   → ✅ Prefer（向后兼容）

---

## Target Platform

**Hermes Agent** is the current primary integration path, **not a permanent constitutional constraint**.

TriAgentFlow / TAF 定位为通用工程协作治理协议，可能在未来适配其他 Agent 平台（Codex / Claude Code / etc.）。

Hermes integration can remain the primary path, but TriAgentFlow / TAF must not be documented as Hermes-only.

---

## Allowed Patterns

### Worker Shards (v1.7 Controlled Parallelism)
- ✅ `execution_mode: parallel_safe`
- ✅ 每个 shard 独立 `worker_id` / `scope` / `forbidden_paths`
- ✅ Verifier Join Verification
- ✅ phase_gate Join Gate

这是 Worker 的受控并行扩展，不是新核心 Agent。

### Optional Schema Fields
- ✅ `review_findings` (v1.8)
- ✅ `evidence_type: OBSERVED` (v1.6)
- ✅ 保持向后兼容

### Review Modes (v1.8)
- ✅ standard / strict / release
- ✅ 审查强度分级，不是新 Agent

### Planning Protocol (v1.8)
- ✅ phases.json / CURRENT_PLAN.md / DECISION_LOG.md / RISK_REGISTER.md
- ✅ Leader 规划产物，不是新 Agent

---

## Prohibited Patterns

### New Core Agent Roles
- ❌ Coordinator / Manager / Aggregator
- ❌ JoinVerifier / ReviewAgent / ApprovalAgent
- ❌ Scheduler / Dispatcher

### Heavy Infrastructure
- ❌ Runtime process / Daemon
- ❌ SQLite / PostgreSQL / MySQL
- ❌ Redis / Memcached
- ❌ Dashboard / Web UI / IDE 插件

### Complex Abstractions
- ❌ DAG engine / Task scheduler
- ❌ Dependency graph / Topological sort
- ❌ GraphRAG / AST indexer
- ❌ Docker orchestration / Kubernetes

### Language Bindings
- ❌ TAF SDK for Python / Node / Go
- ❌ Language-specific API wrappers
- ❌ Platform-specific integrations

保持 TriAgentFlow / TAF 为语言无关、平台无关的协议。

---

## Evolution Path

TriAgentFlow / TAF 允许演进，但必须符合五条宪法。

**允许的演进方向**:
- 新增可选协议字段（向后兼容）
- 新增轻量脚本和文档
- 新增 eval cases（验证协议生效）
- 优化现有门禁逻辑（不破坏兼容性）
- 适配新 Agent 平台（保持协议通用性）

**禁止的演进方向**:
- 新增核心 Agent 角色
- 引入重型基础设施
- 绑定特定语言和工具
- 绕过门禁和证据链
- 成为平台而非协议

---

## Enforcement

这些边界主要通过以下方式执行：

1. **Human Review in PR**  
   - Reviewer 检查：是否触犯五条宪法？
   - CONTRIBUTING.md 引用本文档

2. **Complexity Budget**  
   - 明确文件/脚本/依赖预算
   - 超预算需要明确理由和批准

3. **Gate Test Policy**  
   - 门禁变更强制负向测试
   - 确保门禁真的生效

4. **Protocol Eval Harness**  
   - 验证协议和门禁是否按预期工作
   - 防止协议漂移

5. **Documentation Consistency**  
   - README / HERMES / PROTOCOL 口径对齐
   - 防止定位漂移

---

## Summary

TriAgentFlow / TAF 的核心是：

**三个 Agent（Leader / Worker / Verifier）+ 文件协议 + 门禁机制 + 证据链 + 通用治理抽象 + 轻量实现**

任何偏离这个核心的提议，都必须经过五条宪法检查。

保持 TriAgentFlow / TAF 的简单、通用、可审计，是项目长期成功的关键。

---

**Document Version**: 2.0  
**Last Updated**: 2026-06-10  
**Status**: Authoritative
