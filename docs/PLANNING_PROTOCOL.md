# TriAgentFlow / TAF Planning Protocol

**Version**: 1.8.0  
**Purpose**: 文件化规划层，让规划、决策、风险不依赖对话上下文

---

## Overview

TriAgentFlow / TAF Planning Protocol 定义如何通过文件产出规划、决策和风险跟踪，使协作过程可追溯、可复盘。

---

## Planning Files

### 1. phases.json (必需)

**路径**: `.phase_control/phases.json`  
**所有者**: Leader  
**用途**: 定义阶段拆解和验收标准

Leader 必须产出此文件。

参见 [PHASES_SCHEMA.md](PHASES_SCHEMA.md) 了解 canonical schema。

---

### 2. CURRENT_PLAN.md (可选，复杂项目建议)

**路径**: `docs/planning/CURRENT_PLAN.md` 或 `.phase_control/CURRENT_PLAN.md`  
**所有者**: Leader  
**用途**: 详细规划说明

**包含内容**:
- 项目目标
- 阶段拆解理由
- 验收标准细节
- 已知风险
- 依赖关系
- 时间估算（可选）

**示例片段**:
```markdown
# Current Plan: Historical v1.8 Implementation Example

## Goal
实现 Deterministic Governance Hardening

## Phases
1. Boundaries & Positioning — 明确项目边界
2. Runtime Entry & Schema — 标准化 phases.json
3. Planning Protocol — 本文档
...

## Known Risks
- 文档膨胀风险：控制在 7 个核心文档
- Schema 破坏兼容性：采用 canonicalize not hard-break 策略

## Dependencies
- Phase 2 必须在 Phase 5 前完成（eval 需要 schema validation）
```

---

### 3. DECISION_LOG.md (可选，重大决策建议)

**路径**: `docs/planning/DECISION_LOG.md` 或 `.phase_control/DECISION_LOG.md`  
**所有者**: Leader  
**用途**: 记录重大决策和理由

**格式**:
```markdown
## D001: Decision Title

**Date**: YYYY-MM-DD  
**Context**: 背景说明  
**Options**:
1. Option A
2. Option B

**Decision**: Option X  
**Reason**: 选择理由  
**Impact**: 影响范围
```

**示例**:
```markdown
## D001: Use Manual Delegation

**Date**: 2026-06-03  
**Context**: orchestrator.py 不可用  
**Decision**: 使用 manual delegation  
**Reason**: Manual path 是合法主路径 fallback  
**Impact**: Leader 手动管理 phase transitions
```

---

### 4. RISK_REGISTER.md (可选，已知风险建议)

**路径**: `docs/planning/RISK_REGISTER.md` 或 `.phase_control/RISK_REGISTER.md`  
**所有者**: Leader  
**用途**: 跟踪已知风险和缓解措施

**格式**:
```markdown
## R001: Risk Title

**描述**: 风险描述  
**影响**: High/Medium/Low  
**概率**: High/Medium/Low  
**缓解措施**: 如何缓解  
**状态**: Open/Mitigated/Closed
```

**示例**:
```markdown
## R001: 文档膨胀

**描述**: v1.8 可能新增过多文档  
**影响**: Medium  
**概率**: Medium  
**缓解措施**: 控制在 7 个核心文档，合并 Gate Test Policy 和 Release Governance  
**状态**: Mitigated
```

---

## When to Use

### 简单任务
- 只需 `phases.json`

### 复杂项目
- 建议使用 `CURRENT_PLAN.md`
- 战略决策建议使用 `DECISION_LOG.md`
- 已知风险建议使用 `RISK_REGISTER.md`

---

## Integration with Audit Pack

Planning files 应被 `pack-all-to-md.sh` 包含：
- 帮助外部审计理解规划意图
- 防止上下文漂移

但不应包含敏感内部材料。

---

## Templates

模板片段见 [PLANNING_TEMPLATES.md](PLANNING_TEMPLATES.md)。

不单独建 3 个独立模板文件，避免文件膨胀。

---

**Document Version**: 1.8.0  
**Last Updated**: 2026-06-03  
**Status**: Authoritative
