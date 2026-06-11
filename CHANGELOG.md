# TriAgentFlow Changelog

*Formerly HTE / Hermes Team Engine.*

All notable changes to TriAgentFlow / TAF will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.9.0] - 2026-06-06

### Added
- **Release Gate**: `scripts/hmte-release-gate.sh` — 外圈门禁，检查 P0/P1/P2 状态、dogfood audit pack、external audit receipt，输出 PASS/FAIL/PENDING
- **Release Gate Protocol**: `docs/RELEASE_GATE_PROTOCOL.md` — Release gate 协议文档，明确 fail-closed 语义
- **Audit Pack Modes**: `scripts/hmte-audit-pack.sh` — 支持 core/delta/dogfood/full 四种审计模式，输出 Markdown 报告
- **Audit Pack Modes Documentation**: `docs/AUDIT_PACK_MODES.md` — 四种模式说明、用法、产物路径
- **Dogfood Checklist v1.9**: `docs/DOGFOOD_CHECKLIST_v1.9.md` — 覆盖 Leader/Worker/Verifier/phase_gate/release gate/audit pack/public-safe 等检查项
- **Eval Cases E008-E017**: 10 个 release gate eval cases
  - E008: Release gate P0 blocking
  - E009: Release gate P1 blocking
  - E010: Release gate missing dogfood
  - E011: Audit pack invalid mode
  - E012: Audit pack core gate fail
  - E013: Release gate lint failure blocking (fail-closed hardening)
  - E014: Release gate final-check failure blocking (fail-closed hardening)
  - E015: Release gate sensitive tarball staging blocking
  - E016: Release gate failed dogfood pack blocking
  - E017: Strict release mode requires a valid external audit receipt with open P0/P1 = 0

### Changed
- **Release Gate fail-closed hardening**: lint/final-check 失败不再被当作 PASS，计为 P1 并 FAIL
- **Eval Harness**: required cases 从 E001-E007 增加到 E001-E017，版本升至 1.9.0
- **pack-all-to-md.sh**: 新增 v1.9.0 文件到 tar 模式列表，修复 `*_PLAN*.md` 排除规则过宽导致 IMPLEMENTATION_PLAN 被排除的问题
- **VALIDATION_SUMMARY.md**: 更新为 v1.9.0，eval 16/16
- **CHANGELOG.md**: 新增 v1.9.0 条目
- **docs/README.md**: 新增 v1.9.0 文档索引
- **docs/COMPLEXITY_BUDGET.md**: 新增 v1.9.0 增量预算

### Fixed
- **hmte-release-gate.sh**: lint 失败时不再 `CHECKS_PASS++`，改为计 P1 并 FAIL
- **hmte-release-gate.sh**: final-check 失败时不再 `CHECKS_PASS++`，改为计 P1 并 FAIL
- **hmte-release-gate.sh**: `|| true` 导致 lint exit code 丢失的 bug，改为 `&& LINT_EXIT=0 || LINT_EXIT=$?`
- **hmte-release-gate.sh**: `--project-root` 参数解析 bug，改为 while 循环正确解析
- **hmte-release-gate.sh**: 敏感文件 staging 检查 `grep "*.tar.gz"` 正则漏检，改为 `case` glob 逐文件匹配
- **hmte-release-gate.sh**: dogfood pack 检查只看文件存在不看结果，改为必须包含 `**Result: PASS**` 才通过

### Documentation
- Release gate 是外圈门禁，不是新 Agent
- Audit pack 产物放 `.phase_control/audits/`，不提交 Git
- Dogfood checklist 是检查清单，不实现 workflow selector / recipe

### Backward Compatibility
- 所有 v1.8 测试继续通过
- E001-E007 eval cases 不变
- release gate 是新增功能，不影响现有工作流

## [1.8.0] - 2026-06-03

### Added
- **Project Boundaries & Design Principles**: `docs/PROJECT_BOUNDARIES.md` 明确五条宪法具象化，定义 TAF 边界
- **Runtime Entry & Schema Alignment**: `docs/RUNTIME_ENTRY.md` 和 `docs/PHASES_SCHEMA.md`，明确主路径（Leader→Worker→Verifier→gate）vs 辅助路径（hmte run）
- **phases.json Canonical Schema**: 统一为 `phase_id` / `goal` / `acceptance_criteria`，废弃 `id` / `name` / `objective` / `description`
- **hmte-validate-phases.sh**: 轻量 jq-based validation，默认 WARN deprecated fields，release 模式 FAIL
- **Planning Protocol**: `docs/PLANNING_PROTOCOL.md` 和 `docs/PLANNING_TEMPLATES.md`（含模板片段），支持文件化规划、决策、风险
- **Validation Map**: `docs/VALIDATION_MAP.md`（含 Gate Test Policy），定义"改什么验证什么"的通用映射
- **Protocol Eval Harness**: `scripts/hmte-eval.sh` 和 7 个 eval cases（E001-E003 MVP + E004-E007 P0 fail-closed），验证门禁是否真的生效
- **Verifier Findings**: `verdict-schema.json` 新增 `review_findings` 可选字段（category/severity/confidence/finding/evidence/recommended_action）
- **Review Modes**: HTE_PROTOCOL.md 新增 Review Modes（standard/strict/release）章节
- **Complexity Budget**: `docs/COMPLEXITY_BUDGET.md`（含 Release Governance），明确文件/脚本/依赖预算

### Changed
- **战略定位硬化**: README / HERMES / PROTOCOL / SKILL 表述调整为通用工程协作治理协议（不只是代码测试）
- **术语统一**: 全文使用 "Final Verifier"（release_gate 外圈门禁），不再使用 "Release Auditor"
- **Schema 策略**: canonicalize not hard-break，默认 WARN deprecated fields，release 模式 FAIL
- **Manual Delegation Fallback**: 明确为合法主路径 fallback，必须记录在 DECISION_LOG

### Documentation
- 新增 7 个核心文档（PROJECT_BOUNDARIES / RUNTIME_ENTRY / PHASES_SCHEMA / PLANNING_PROTOCOL / VALIDATION_MAP / COMPLEXITY_BUDGET / PLANNING_TEMPLATES）
- 适用场景扩展：代码开发、文档工作、配置变更、AI Skill 开发、Release 流程

### Backward Compatibility
- 所有 v1.7 测试继续通过（91/91 E2E）
- phases.json deprecated fields 默认只 WARN，不强制破坏
- review_findings / review_modes 为可选，不影响现有工作流

## [1.7.0] - 2026-06-02

### Added
- **Controlled Parallelism**: `execution_mode: parallel_safe` — Phase 内受控并行，多个 Worker Shard 同时执行
- **Worker Shard**: 每个 shard 有独立 `worker_id`、`scope`、`forbidden_paths`，写独立 evidence 和 command log
- **Verifier Join Verification**: `join_verification` verdict block — Verifier 必须审计全部 shard evidence
- **phase_gate Join Gate**: 12 项硬校验 — worker_id 合法性、evidence/command-log 存在性、路径覆盖、文件冲突、状态一致性
- **hmte-exec.sh --worker-id**: 并行 Worker 显式传 worker_id，隔离 command log 路径
- **Parallel Run Ledger Events**: parallel_phase_started、worker_shard_delegated、worker_shard_evidence_ready、join_verification_result、parallel_phase_gate_result
- **e2e-parallel-workflow-test.sh**: 31 个 E2E 测试覆盖 parallel_safe 正向/负向、final-check shard-aware、安装态 fail-closed、duplicate worker_id、command log 内容校验场景

### Changed
- `docs/HTE_PROTOCOL.md` 新增 §9 Controlled Parallelism（§9.1–9.9）
- `hmte-final-check.sh` 支持 `parallel_safe` shard-only 最终文件链检查
- `hmte-audit-flow.py` 对 parallel shard command log 执行完整 JSONL 内容校验
- `README.md` / `CHANGELOG.md` 版本更新到 v1.7
- `src/skills/hmte/SKILL.md` 适配 parallel_safe Worker/Verifier 模板

### Backward Compatibility
- Sequential phases（无 `execution_mode`）完全不受影响
- 所有 v1.6 E2E 测试保持 100% 通过
- verdict-schema.json 不修改（新增字段均为可选）

## [1.6.0] - 2026-06-02

### Added
- **HTE_PROTOCOL 单一权威文档**：将协议、字段与门禁口径收敛到 `docs/HTE_PROTOCOL.md`
- **Run Ledger**：新增 `.phase_control/run_ledger.jsonl` 事件流，记录 orchestrator / gate 关键动作
- **Workflow Templates**：新增 `src/skills/hmte/templates/workflows.yaml`，便于复用三 Agent 和 release 流程
- **Evidence Schema 扩展**：支持可选字段扩展，同时保持旧格式兼容

### Changed
- README / HERMES / protocol 文档口径更新到 v1.6
- Final Verifier 明确为 release_gate 外圈门禁，非第四核心 Agent
- pack-all-to-md.sh 改为包含最终测试结果文件，并排除旧审计包与套娃产物
- hmte-status.sh 增强 Run Ledger 展示

### Tests
- 最终验证命令 20/20 通过
- e2e-core-workflow-test.sh: 10/10
- e2e-anti-fake-test.sh: 12/12
- e2e-p0-hardening-test.sh: 10/10
- e2e-verifier-adversarial-test.sh: 12/12
- e2e-lifecycle-test.sh: 16/16
- HMTE_LINT_MODE=release bash scripts/hmte-lint-protocol.sh: PASS（0 FAIL, 2 WARN）

### Complexity Budget
- Modified files only, no new dependencies, no new runtime components
- New tracked files: 0
- Code movement concentrated in docs, pack script, and verification evidence

## [1.5.0] - 2026-06-01

### Added (P0)
- **Verifier Cross-Validation**: Enhanced phase_gate.sh with P0 mandatory fields (verification_method, risk_disposition, re_verification_conclusion)
- **Type Safety**: Implemented as_list(), as_dict(), as_bool() normalization functions in phase_gate.sh
- **Amendment Lock Tightening**: Hash normalization, phase binding check, reason length validation in hmte-goal-lock.sh
- **Verifier Adversarial Test Suite**: 12 adversarial test cases with one-bad-thing-per-case principle (e2e-verifier-adversarial-test.sh)

### Added (P1)
- **Instruction Lint Extension**: 30 dangerous weakening phrases (15 Chinese + 15 English) in hmte-lint-instructions.sh
- **Red Team Documentation**: red-team-prompts.md, red-team-evaluation.md, red-team-results.md
- **hmte-doctor**: Lightweight diagnostic script (54 checks, diagnose-only mode)
- **Receipt Compatibility**: Support both trust_level and delegation_trust_level formats in hmte-audit-flow.py

### Changed
- phase_gate.sh: Enhanced with P0 field validation and exemption logic tightening
- hmte-goal-lock.sh: Hash normalization implementation for consistent SHA256 calculation
- hmte-final-check.sh: Phase binding check and release mode blocking for invalid amendments
- hmte-audit-flow.py: Backward compatibility for old and new receipt formats

### Fixed
- e2e-anti-fake-test.sh: Updated verdict format to include P0 mandatory fields
- src/skills/hmte/scripts/phase_gate.sh: Added execute permission

### Complexity Budget
- New code: ~514 lines (modified) + ~3051 lines (new files) = ~3565 lines
- New files: 10 (4 test scripts + 3 red team docs + 3 planning docs)
- New dependencies: 0

## [1.4.0] - 2026-05-30

### Added
- **Leader Jail** — 项目面改动必须有完整 ownership chain（evidence + receipt + command log + verdict + phase_gate）
- **Goalpost Lock** — SHA256 锁定验收标准，检测后续弱化/删除/新增 phase
- **Instruction Lint** — 检测"只检查格式"类危险弱化语句
- **Evidence Claim Verification** — 验证每个 claimed file 真实存在 + 在 git diff 中 + 在 command log 中
- **Verifier Minimum Audit** — 强制 verdict 包含 independently_verified_files 和 re_verification_conclusion
- **Final Check v2** — 完整链路检查（7-file 完整性 + 全部 P0 检查 + Leader Jail）
- **Profile/Global Dual-Path Installer** — install-to-hermes.sh 支持 --profile 和 --all 模式
- **E2E P0 Hardening Tests** — 新增 T1-T10 覆盖 Leader Jail、Goalpost Lock、新增 phase 检查

### Changed
- README / HERMES / SKILL 统一到 v1.4 工作流（install → kickoff → goal lock → final-check release）
- final-check 现在是主流程门禁，未通过的完成声明视为无效
- hmte-verify-claims.sh 现在覆盖 working tree + staged + committed + untracked 改动（与 Leader Jail 一致）
- Goalpost Lock 现在检测新增 phase，release 模式下要求 amendment 授权

### Security
- 硬化项目面 ownership chain，Leader 不能直接改项目文件
- 阻止弱化 instruction patterns（"只检查格式"、"不运行测试"等）
- 阻止 goalpost weakening（删除 criteria、删除 phase、新增弱 phase）
- release 模式下 WARN 升级为 FAIL，缺 goal_lock/final_audit/leader-jail 均 FAIL

## [1.2.0] - 2026-05-28

### Added
- Initial release of the legacy HTE / Hermes Team Engine workflow
- Leader/Worker/Verifier multi-agent architecture
- Phase-based workflow with quality gates
- Evidence-driven verification system
- State machine tracking with `.phase_control/state.json`
- Safety enforcement with pretool guards and stop gates
- Cross-platform support (Linux, macOS, Windows with Git Bash)
- Comprehensive documentation and examples
- E2E testing framework
- Installation script for Hermes integration
- MIT License

### Changed
- Migrated from Claude Code to Hermes Agent platform
- Renamed from internal codename to legacy HTE / Hermes Team Engine
- Updated all agent definitions to Hermes format
- Consolidated all scripts with `hmte-` prefix
- Improved Windows compatibility (fcntl fallback, python vs python3)

### Fixed
- Windows compatibility issues with file locking
- Python command compatibility across platforms
- JSON validation fallback when jq is not available
- Documentation references to outdated platform names
- Badge links in README
- Manual testing step numbering

### Security
- Input validation in all shell scripts
- Command injection prevention in evidence collection
- Safe file operations with proper escaping

---

## Version History Notes

This project was originally developed under an internal codename and has been migrated across platforms. Historical documentation and implementation details can be found in `docs/history/`.

For migration details, see:
- `docs/history/PLATFORM_HISTORY.md`
