# TriAgentFlow / TAF Planning Templates

**Version**: 1.8.0  
**Purpose**: 提供 Planning Protocol 模板片段

---

## Overview

本文档提供 CURRENT_PLAN、DECISION_LOG、RISK_REGISTER 的模板片段。

不单独建 3 个独立模板文件，避免文件膨胀。

---

## CURRENT_PLAN Template

用于复杂项目的详细规划。

```markdown
# Current Plan: [Project Name]

**Created**: YYYY-MM-DD  
**Status**: Active/Complete

---

## Goal

[项目目标]

---

## Phases

1. **Phase 1**: [phase_id] — [goal]
   - Acceptance: [criteria]
2. **Phase 2**: [phase_id] — [goal]
   - Acceptance: [criteria]

---

## Known Risks

- **R001**: [risk description]
  - Impact: High/Medium/Low
  - Mitigation: [措施]

---

## Dependencies

- Phase X must complete before Phase Y
- External dependency: [description]

---

## Timeline (Optional)

- Phase 1: Week 1
- Phase 2: Week 2

---

## Notes

[其他说明]
```

---

## DECISION_LOG Template

用于记录重大决策。

```markdown
# Decision Log

## D001: [Decision Title]

**Date**: YYYY-MM-DD  
**Context**: [背景说明]  
**Options**:
1. Option A — [描述]
2. Option B — [描述]

**Decision**: Option X  
**Reason**: [选择理由]  
**Impact**: [影响范围]  
**Trade-offs**: [权衡]

---

## D002: [Next Decision]

...
```

---

## RISK_REGISTER Template

用于跟踪已知风险。

```markdown
# Risk Register

## R001: [Risk Title]

**描述**: [风险描述]  
**影响**: High/Medium/Low  
**概率**: High/Medium/Low  
**缓解措施**: [如何缓解]  
**责任人**: [可选]  
**状态**: Open/Mitigated/Closed  
**更新**: YYYY-MM-DD

---

## R002: [Next Risk]

...
```

---

## Usage Examples

### Example 1: Simple Project

只需 `phases.json`：

```json
{
  "project_name": "Add Login Feature",
  "phases": [
    {
      "phase_id": "implement",
      "goal": "实现登录功能",
      "acceptance_criteria": ["测试通过", "文档完成"]
    }
  ]
}
```

### Example 2: Complex Project

使用 `phases.json` + `CURRENT_PLAN.md` + `DECISION_LOG.md`：

**phases.json**: 阶段定义  
**CURRENT_PLAN.md**: 详细规划和风险  
**DECISION_LOG.md**: 关键技术选型决策

### Example 3: Strategic Decision

使用 `DECISION_LOG.md` 记录：

```markdown
## D001: Choose Schema Strategy

**Date**: 2026-06-03  
**Context**: v1.8 需要标准化 phases.json schema  
**Options**:
1. Hard-break: 强制新 schema
2. Canonicalize: 标准化但不破坏

**Decision**: Canonicalize (default WARN, release FAIL)  
**Reason**: 向后兼容，不破坏现有项目  
**Impact**: orchestrator 需要 normalize 旧 schema
```

---

## Integration with TriAgentFlow / TAF

Planning files 存放位置：

1. **Runtime planning** (项目执行中):
   - `.phase_control/CURRENT_PLAN.md`
   - `.phase_control/DECISION_LOG.md`
   - `.phase_control/RISK_REGISTER.md`

2. **Project-level planning** (长期规划):
   - `docs/planning/CURRENT_PLAN.md`
   - `docs/planning/DECISION_LOG.md`
   - `docs/planning/RISK_REGISTER.md`

选择取决于规划的生命周期和可见性需求。

---

## References

- [PLANNING_PROTOCOL.md](PLANNING_PROTOCOL.md) — 详细协议说明
- [PHASES_SCHEMA.md](PHASES_SCHEMA.md) — phases.json 标准

---

**Document Version**: 1.8.0  
**Last Updated**: 2026-06-03  
**Status**: Authoritative Template Reference
