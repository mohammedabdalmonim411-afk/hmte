# TriAgentFlow / TAF Complexity Budget

**Version**: 2.0（v1.9.0 内容保留为历史参考）  
**Purpose**: 防止项目膨胀，明确文件/脚本/依赖预算

*Formerly HTE / Hermes Team Engine. The `hmte` command prefix is retained as a legacy compatibility prefix.*

---

## Purpose

TriAgentFlow / TAF 必须保持轻量、可维护、可审计。

本文档明确新增文件、脚本、依赖的预算，防止项目膨胀。

---

## File Budget

### 当前规模（v1.7 baseline）

| 类型 | 数量 |
|------|------|
| 核心文档 | 10 个（README / HERMES / PROTOCOL / etc.） |
| Agent 定义 | 4 个（Leader / Worker / Verifier / Final Verifier 说明） |
| 核心脚本 | 32 个（scripts/*.sh） |
| Python 脚本 | 6 个（orchestrator / audit-flow / etc.） |
| E2E 测试 | 6 个套件（91 个测试） |
| Schema 文件 | 3 个（evidence / verdict / receipt） |

### v1.8 预算

| 类型 | 允许新增 | 理由 |
|------|---------|------|
| 核心文档 | **+7 个** | PROJECT_BOUNDARIES / RUNTIME_ENTRY / PHASES_SCHEMA / PLANNING_PROTOCOL / VALIDATION_MAP / COMPLEXITY_BUDGET / PLANNING_TEMPLATES |
| Agent 定义 | **0 个** | 三 Agent 不变 |
| 核心脚本 | **+3 个** | hmte-validate-phases.sh / hmte-eval.sh / phase_gate.sh (wrapper) |
| Python 脚本 | **0 个** | 不新增 |
| E2E 测试 | **0 个套件** | eval cases 不是独立套件 |
| Schema 文件 | **0 个** | 只修改现有 schema（新增可选字段） |
| Eval cases | **+7 个** | E001-E003（MVP）+ E004-E007（P0 fail-closed regression） |

---

## Script Budget

### 新增脚本原则
- 必须有明确用途，不是"可能有用"
- 必须轻量（< 500 行）
- 必须可测试
- 必须有文档

### 禁止新增
- ❌ Daemon 守护进程
- ❌ 后台服务
- ❌ 数据库脚本
- ❌ 复杂状态机
- ❌ 测试框架抽象

---

## Dependency Budget

### 当前依赖（v1.7 baseline）

**必需**:
- bash（系统自带）
- python3（系统自带或用户安装）
- jq（JSON 处理）
- git（版本控制）

**可选**:
- hermes（运行时）

### v1.8 预算

| 类型 | 允许 |
|------|------|
| 新增必需依赖 | **0 个** |
| 新增可选依赖 | **0 个** |
| 新增 Python 包 | **0 个** |

### 禁止引入
- ❌ SQLite / PostgreSQL / MySQL
- ❌ Redis / Memcached
- ❌ Docker / Kubernetes
- ❌ Node.js / npm packages
- ❌ GraphQL / gRPC
- ❌ 机器学习库（TensorFlow / PyTorch）
- ❌ AST 解析库
- ❌ GraphRAG 相关库

---

## Protocol Field Budget

### 新增字段原则
- 必须可选（保持向后兼容）
- 必须有明确用途
- 必须通用（不绑定特定场景）

### v1.8 预算

| Schema | 允许新增 |
|--------|---------|
| evidence-schema.json | **0 个新增字段** |
| verdict-schema.json | **1 个**（review_findings，可选） |
| delegation-receipt-schema.json | **0 个新增字段** |
| phases.json | **0 个**（只标准化现有字段名） |

---

## Test Budget

### 测试要求
- Gate / protocol 变更必须有负向测试
- 新增能力必须有 E2E 覆盖
- 不追求 100% 覆盖率（重点覆盖关键路径）

### v1.8 预算

| 类型 | 允许新增 |
|------|---------|
| E2E 测试 | **0 个独立套件** |
| Eval cases | **7 个**（MVP: E001-E003 + P0 fail-closed: E004-E007） |
| 单元测试 | **不做**（TAF 是集成系统） |

---

## Release Governance

### 每个版本收尾必须

**P0（阻断）**:
- ✅ Public-safe cleanup（删除内部审计包、临时报告）
- ✅ 检查仓库体积（不超过 10MB，排除 .git）
- ✅ 检查内部材料（无残留 test_results.log）
- ✅ 检查旧审计包（无 HTE_v*.md）
- ✅ 运行 public-safe grep checks
- ✅ **Full Dogfood Release Gate**: 每个大版本封版前必须完整跑通 full dogfood release gate。要求 P0=0, P1=0，只允许极少数明确可接受的 P2。否则不得封版，必须最小修补后重新 dogfood 回归。

**P1（强烈建议）**:
- ✅ CHANGELOG.md 更新
- ✅ VALIDATION_SUMMARY.md 生成
- ✅ Git tag 创建
- ✅ 所有 E2E 测试通过

**P2（可选）**:
- ⏸ GitHub Release 创建
- ⏸ 外部审计报告

### Public-Safe Grep Checks

Release 前必须运行：

```bash
# 生成测试审计包
bash scripts/pack-all-to-md.sh --markdown TEST_PACK.md

# Public-safe checks
grep "/Users/" TEST_PACK.md
# 预期：无输出

grep "reviewer" TEST_PACK.md
# 预期：无输出

grep "Logged to: .phase_control" TEST_PACK.md
# 预期：无输出

grep "## File: `test_results.log`" TEST_PACK.md
# 预期：无输出

# 清理
rm TEST_PACK.md
```

### .gitignore Coverage

确保 .gitignore 覆盖：

```
# Audit packs and release reports
HTE_v*.md
TAF_v*.md
TriAgentFlow_v*.md
*_AUDIT*.md
*_RELEASE_CONFIRMED.md
*_PLAN*.md
*_PATCH*.md
test_results.log

# Internal planning
dev/planning/*PLAN*.md
dev/planning/*PATCH*.md

# Runtime
.phase_control/
.phase_control_archive/
```

### pack-all-to-md.sh Alignment

pack-all-to-md.sh 的排除规则必须与 .gitignore 对齐。

### Post-Release Cleanup

发布后立即：

```bash
# 删除本地审计包和临时报告
rm -f HTE_v*_AUDIT*.md
rm -f *_RELEASE_CONFIRMED.md
rm -f *_PLAN*.md
rm -f *_PATCH*.md
rm -f test_results.log
rm -f PUBLIC_SAFE_*.md
rm -f CLEANUP_*.md
rm -f FINAL_FIX_*.md
```

### 大版本结束必须

- ✅ 审查文档膨胀（是否可合并）
- ✅ 审查脚本膨胀（是否可合并）
- ✅ 审查测试膨胀（是否可优化）
- ✅ 审查依赖（是否可减少）

---

## Enforcement

- 人工 PR review
- CONTRIBUTING.md 引用本预算
- Reviewer 检查：是否超预算？
- 超预算需要明确理由和批准

---

## Exceptions

如需超预算，必须：

1. 在 PR 中明确说明理由
2. 讨论是否有更轻量的替代方案
3. 获得维护者批准
4. 更新本预算文档

---

## v1.8 Summary

v1.8 新增：
- ✅ 7 个核心文档
- ✅ 3 个脚本 (hmte-validate-phases.sh, hmte-eval.sh, phase_gate.sh wrapper)
- ✅ 7 个 eval cases（E001-E003 为 MVP，E004-E007 为 P0 修复所需的最小负向测试）
- ✅ 1 个可选 schema 字段（review_findings）
- ✅ 0 个新依赖
- ✅ 0 个新核心 Agent

**总体评估**: 符合"不过度工程"宪法 ✅

---

## v1.9.0 Summary

v1.9.0 新增：
- ✅ 2 个脚本 (hmte-release-gate.sh, hmte-audit-pack.sh)
- ✅ 3 个文档 (RELEASE_GATE_PROTOCOL.md, AUDIT_PACK_MODES.md, DOGFOOD_CHECKLIST_v1.9.md)
- ✅ 9 个 eval cases（E008-E012: release gate & audit pack, E013-E014: fail-closed hardening, E015: sensitive tarball blocking, E016: failed dogfood pack blocking）
- ✅ 0 个新依赖
- ✅ 0 个新核心 Agent

**总体评估**: 符合"不过度工程"宪法 ✅

---

**Document Version**: 1.9.0  
**Last Updated**: 2026-06-06  
**Status**: Authoritative
