# Workflow Recipe: Gate Script Enhancement

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Deprecated**: No  
**Supersedes**: v1.0  
**Category**: Core Infrastructure  
**Risk Level**: P0  
**Plan Items Required**: ["S-xxx", "AC-xxx", "T-xxx", "NT-xxx"]  

---

## Overview

High-risk recipe for modifying core gate scripts (phase_gate.sh, release_gate.sh, final-check.sh). These scripts enforce governance boundaries and must maintain fail-closed behavior.

---

## When to Use

Use this recipe when:
- Adding new checks to `phase_gate.sh`
- Modifying `release_gate.sh` logic
- Updating `final-check.sh` validation
- Adding new gate configuration options
- Integrating new P0 capability checks

Do NOT use for:
- Non-gate script changes
- Documentation-only updates
- Optional helper scripts (use standard workflow)

---

## Plan Item Requirements

| Plan Item Type | Minimum Count | Example IDs |
|----------------|---------------|-------------|
| Scope Item | 1 | S-005 |
| Acceptance Criteria | 3+ | AC-005, AC-006, AC-007 |
| Required Tests | 4+ | T-005, T-006, T-007, T-008 |
| Required Negative Tests | 3+ | NT-005, NT-006, NT-007 |
| Risk Items | 1+ | R-005 |

---

## Phases

### Phase 1: Requirement Analysis

**Plan Items**: [S-xxx, AC-xxx]

**Steps**:
1. Document new check requirement
2. Identify fail-closed vs fail-open scenarios
3. Design check logic and error messages
4. Plan integration point in gate script

**Evidence Required**:
- `requirement_doc.md`: Detailed requirement
- `fail_closed_analysis.md`: Fail-closed scenarios
- `integration_plan.md`: Where and how to integrate

**Acceptance Criteria**: [AC-xxx]
- Requirement documented
- Fail-closed behavior specified
- Integration plan approved

---

### Phase 2: Implementation

**Plan Items**: [S-xxx, AC-xxx]

**Steps**:
1. Modify gate script with new check
2. Add error handling (fail-closed)
3. Add verbose logging
4. Update gate config schema if needed

**Evidence Required**:
- `changed_files`: Gate script path
- `command_logs`: Syntax check, shellcheck
- `code_diff.txt`: Git diff of changes

**Acceptance Criteria**: [AC-xxx]
- Check implemented
- Fail-closed on error
- Shellcheck passes
- Code reviewed

---

### Phase 3: Positive Testing

**Plan Items**: [T-xxx]

**Steps**:
1. Create test fixture with valid input
2. Run gate script with valid input
3. Verify gate PASS
4. Verify correct log output

**Evidence Required**:
- `changed_files`: Test fixture files
- `command_logs`: Gate script execution
- `tests_run`: Test case names
- `test_output.txt`: Full gate output

**Acceptance Criteria**: [AC-xxx]
- Valid input → gate PASS
- Log output correct
- No false positives

---

### Phase 4: Negative Testing

**Plan Items**: [NT-xxx]

**Steps**:
1. Create negative test fixtures
2. Test missing required field → gate FAIL
3. Test invalid field value → gate FAIL
4. Test edge cases → gate FAIL
5. Verify fail-closed on error

**Evidence Required**:
- `changed_files`: Negative test fixtures
- `command_logs`: Gate script execution
- `tests_run`: All negative test names
- `tests_failed`: Empty (negative tests should detect violations)
- `negative_test_report.md`: Summary of all negative tests

**Acceptance Criteria**: [AC-xxx]
- All negative tests detect violations
- Gate FAIL on invalid input
- Fail-closed on error
- Error messages clear

**Required Negative Tests** (minimum 3):
1. Missing required field
2. Invalid field value
3. Malformed input

---

### Phase 5: Integration Testing

**Plan Items**: [T-xxx]

**Steps**:
1. Run gate script on real evidence bundle
2. Verify backward compatibility with v1.9 evidence
3. Run full eval harness
4. Test gate with all intensity configs

**Evidence Required**:
- `command_logs`: Eval harness execution
- `tests_run`: All eval case names
- `eval_output.txt`: Full eval output
- `backward_compat_test.md`: v1.9 compatibility results

**Acceptance Criteria**: [AC-xxx]
- Eval harness PASS
- Backward compatible
- All intensity configs work

---

### Phase 6: Fail-Closed Verification

**Plan Items**: [NT-xxx]

**Steps**:
1. Test gate behavior on script error
2. Test gate behavior on missing dependency
3. Test gate behavior on malformed JSON
4. Verify all error paths fail-closed

**Evidence Required**:
- `command_logs`: Error scenario tests
- `fail_closed_report.md`: All error scenarios tested
- `tests_run`: Fail-closed test names

**Acceptance Criteria**: [AC-xxx]
- Script error → gate FAIL
- Missing dependency → gate FAIL
- Malformed input → gate FAIL
- No false PASS

---

## Gate Configuration

**Recommended Intensity**: strict

**Gate Config**: `docs/intensity-configs/gate-strict.json`

**Required Gate Checks**:
- evidence_required: true
- verdict_required: true
- command_log_required: true
- negative_tests_required: true
- min_negative_tests: 3
- eval_harness_required: true

---

## Pitfalls

| Pitfall | Mitigation |
|---------|------------|
| False PASS on error | Require explicit fail-closed checks |
| Breaking v1.9 compatibility | Test against v1.9 evidence bundles |
| Unclear error messages | Require error message review |
| Missing negative tests | Require 3+ negative tests per new check |
| Untested edge cases | Require edge case test plan |

---

## Verification

### Required Tests

- Positive test (valid input)
- Missing required field (negative)
- Invalid field value (negative)
- Malformed input (negative)
- Script error (fail-closed)
- Backward compatibility

### Required Artifacts

- Gate script with changes
- Test fixtures (positive + negative)
- Fail-closed verification report
- Eval harness output

### Required Command Logs

- Shellcheck
- Positive test execution
- All negative test executions
- Eval harness execution
- Backward compatibility test

---

## Success Criteria

- [ ] New check implemented
- [ ] Fail-closed verified
- [ ] All negative tests pass
- [ ] Eval harness PASS
- [ ] Backward compatible
- [ ] Shellcheck passes
- [ ] Documentation updated

---

## Example Usage

```bash
# Generate phases.json from this recipe
bash scripts/hmte-recipe-compose.sh \
  --recipe docs/recipes/recipe-gate-enhancement.md \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-items "S-005,AC-005,AC-006,AC-007,T-005,T-006,NT-005,NT-006,NT-007" \
  --output .phase_control/phases.json
```

---

**Last Updated**: 2026-06-10  
**Maintainer**: TAF Core Team
