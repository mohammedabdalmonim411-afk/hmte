# Workflow Recipe: Schema Change

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Deprecated**: No  
**Supersedes**: v1.0  
**Category**: Core Protocol  
**Risk Level**: P0  
**Plan Items Required**: ["S-xxx", "AC-xxx", "T-xxx"]  

---

## Overview

High-risk recipe for changes to core TAF schemas (evidence-schema.json, verdict-schema.json, plan_lock.json, etc.). Requires strict governance and comprehensive negative testing.

---

## When to Use

Use this recipe when:
- Modifying `evidence-schema.json`
- Modifying `verdict-schema.json`
- Modifying `plan_lock.json`
- Adding new required fields to existing schemas
- Changing schema validation logic

Do NOT use for:
- Documentation-only changes
- Adding optional fields (use standard workflow)
- Non-schema protocol changes

---

## Plan Item Requirements

This recipe requires the following plan items:

| Plan Item Type | Minimum Count | Example IDs |
|----------------|---------------|-------------|
| Scope Item | 1 | S-001 |
| Acceptance Criteria | 2+ | AC-001, AC-002 |
| Required Tests | 3+ | T-001, T-002, T-003 |
| Required Negative Tests | 2+ | NT-001, NT-002 |
| Risk Items | 1+ | R-001 |

---

## Phases

### Phase 1: Schema Analysis & Impact Assessment

**Plan Items**: [S-xxx]

**Steps**:
1. Identify all files that reference the schema
2. Analyze backward compatibility impact
3. Document breaking vs non-breaking changes
4. Create schema migration plan if needed

**Evidence Required**:
- `changed_files`: Schema file path
- `command_logs`: grep/ripgrep commands showing all references
- `impact_analysis.md`: Document listing affected files

**Acceptance Criteria**: [AC-xxx]
- All schema references identified
- Backward compatibility analyzed
- Migration plan documented if breaking change

---

### Phase 2: Schema Update

**Plan Items**: [S-xxx]

**Steps**:
1. Update schema JSON file
2. Update schema validation logic (if any)
3. Run schema validation test

**Evidence Required**:
- `changed_files`: Schema JSON file, validation scripts
- `command_logs`: Schema validation commands
- `tests_run`: Schema validation tests

**Acceptance Criteria**: [AC-xxx]
- Schema JSON valid
- Validation logic updated
- Backward compatibility preserved (or migration provided)

---

### Phase 3: Update Consumers

**Plan Items**: [S-xxx]

**Steps**:
1. Update scripts that write to schema
2. Update scripts that read from schema
3. Update phase_gate schema checks
4. Update documentation

**Evidence Required**:
- `changed_files`: All consumer scripts, docs
- `command_logs`: Test commands
- `tests_run`: Consumer tests

**Acceptance Criteria**: [AC-xxx]
- All consumers updated
- Tests pass

---

### Phase 4: Negative Testing

**Plan Items**: [T-xxx, NT-xxx]

**Steps**:
1. Test schema validation rejects invalid input
2. Test backward compatibility (if applicable)
3. Test forward compatibility (if applicable)
4. Test phase_gate with missing/invalid schema fields

**Evidence Required**:
- `changed_files`: Test files
- `command_logs`: Test execution
- `tests_run`: All negative test names
- `tests_failed`: Empty (all negative tests must pass)

**Acceptance Criteria**: [AC-xxx]
- All negative tests pass
- Invalid input rejected
- Compatibility verified

---

### Phase 5: Full Protocol Lint

**Plan Items**: [AC-xxx]

**Steps**:
1. Run `HMTE_LINT_MODE=release bash scripts/hmte-lint-protocol.sh`
2. Verify no schema-related errors
3. Run eval harness with schema changes

**Evidence Required**:
- `command_logs`: Lint and eval commands
- `tests_run`: Eval case names
- `lint_output.txt`: Full lint output

**Acceptance Criteria**: [AC-xxx]
- Protocol lint PASS
- Eval harness PASS

---

## Gate Configuration

**Recommended Intensity**: strict

**Gate Config**: `docs/intensity-configs/gate-strict.json`

**Required Gate Checks**:
- evidence_required: true
- verdict_required: true
- command_log_required: true
- negative_tests_required: true
- min_negative_tests: 2
- protocol_lint_required: true
- eval_harness_required: true

---

## Pitfalls

| Pitfall | Mitigation |
|---------|------------|
| Breaking v1.9 compatibility | Test against v1.9 evidence/verdict files |
| Missing schema consumers | Use ripgrep to find all references |
| Incomplete negative tests | Require 2+ negative tests per schema field |
| phase_gate not updated | Update phase_gate schema validation |

---

## Verification

### Required Tests

- Schema validation test (positive)
- Schema validation rejection (negative)
- Backward compatibility test
- Consumer integration test

### Required Artifacts

- `impact_analysis.md`
- Schema JSON file
- Updated consumer scripts
- Negative test cases

### Required Command Logs

- ripgrep for schema references
- Schema validation commands
- Test execution commands
- Protocol lint command

---

## Success Criteria

- [ ] Schema updated and valid
- [ ] All consumers updated
- [ ] All negative tests pass
- [ ] Protocol lint PASS
- [ ] Eval harness PASS
- [ ] Backward compatibility verified
- [ ] Documentation updated

---

## Example Usage

```bash
# Generate phases.json from this recipe
bash scripts/hmte-recipe-compose.sh \
  --recipe docs/recipes/recipe-schema-change.md \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-items "S-001,AC-001,AC-002,T-001,T-002,NT-001,NT-002" \
  --output .phase_control/phases.json
```

---

**Last Updated**: 2026-06-10  
**Maintainer**: TAF Core Team
