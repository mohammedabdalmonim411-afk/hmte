# Phase 4: .hmte/team-rules.md

## Objective
Create lightweight team rules file that defines HTE workflow boundaries and role constraints.

## Scope
- Create `.hmte/team-rules.md`
- Define general rules, role boundaries, and capability boundaries
- Keep content lightweight and actionable

## Success Criteria
- File created with clear structure
- Covers: general rules, role boundaries, capability boundaries
- No Hook engine implementation
- Content aligns with HTE v1.4 capability claims

## Required Structure
```markdown
# HTE Team Rules
## 通用规则
- All Worker commands must go through hmte exec
- evidence must include command_log_path
- PASS verdict criteria_failed must be empty
- final_audit must check README/HERMES/SKILL/scripts consistency

## 角色边界
- Leader does not directly execute Worker implementation tasks
- Worker does not write verdict
- Verifier does not modify business code
- Release Auditor does not fix issues, only does comprehensive audit

## 能力边界
- receipt default is INTENT_ONLY
- OBSERVED requires real tool-call trace
- HTE is currently file protocol workflow, not complete standalone Agent Runtime
```

## Constraints
- Keep lightweight - no complex rule engine
- No Hook implementation
- Align with hmte-claims.sh output
