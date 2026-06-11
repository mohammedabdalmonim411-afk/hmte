# Verifier Audit Checklist

Use this checklist when auditing phase execution results.

## Pre-Audit

- [ ] Read phase spec (objective, acceptance_criteria, required_evidence)
- [ ] Load evidence bundle JSON
- [ ] Understand what was supposed to be delivered

## Evidence Completeness

- [ ] All required_evidence types present
- [ ] changed_files list is non-empty (if code changes expected)
- [ ] commands_run recorded
- [ ] command_exit_codes all documented
- [ ] generated_at timestamp present

## File Verification

- [ ] All changed_files actually exist
- [ ] Files contain expected changes
- [ ] No unexpected file modifications
- [ ] Artifacts referenced in artifact_paths exist

## Test Verification

- [ ] Tests were run (if required)
- [ ] test_results.failed == 0 (or explained)
- [ ] Test coverage adequate
- [ ] Tests actually test the right things

## Build Verification

- [ ] Build succeeded (if applicable)
- [ ] No build errors
- [ ] Build artifacts produced

## Code Quality

- [ ] Lint results acceptable
- [ ] No obvious bugs
- [ ] Follows project conventions
- [ ] Security considerations addressed

## Acceptance Criteria

For each criterion in phase spec:
- [ ] Criterion 1: Met / Not Met / Unclear
- [ ] Criterion 2: Met / Not Met / Unclear
- [ ] Criterion 3: Met / Not Met / Unclear
- [ ] ...

## Risk Assessment

- [ ] Review unresolved_risks
- [ ] Assess severity of each risk
- [ ] Determine if risks are acceptable
- [ ] Check for unlisted risks

## Verification Gaps

- [ ] Review verification_gaps
- [ ] Determine if gaps are critical
- [ ] Assess confidence level
- [ ] Consider if BLOCK needed

## Frontend-Specific (if applicable)

- [ ] Screenshots provided
- [ ] UI matches design
- [ ] No console errors
- [ ] Network requests succeed
- [ ] Performance acceptable

## Backend-Specific (if applicable)

- [ ] API tests pass
- [ ] Error handling complete
- [ ] Security vulnerabilities checked
- [ ] Database migrations work

## Decision

Based on above checks:

### PASS if:
- All acceptance criteria met
- Evidence complete and credible
- No critical unresolved issues
- Acceptable residual risks

### FAIL if:
- Any acceptance criterion not met
- Tests failing
- Critical bugs found
- Evidence insufficient

### BLOCK if:
- Missing required inputs
- Cannot verify due to environment
- Scope issues beyond phase
- Need human decision

## Verdict Output

Write verdict to `.phase_control/verdicts/<phase_id>_attempt_<n>.json`:

```json
{
  "status": "PASS",
  "phase_id": "<phase_id>",
  "attempt": <n>,
  "timestamp": "2024-01-15T10:30:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [
      {
        "criterion": "All acceptance criteria met",
        "evidence": ".phase_control/evidence/<phase_id>_attempt_<n>.json"
      }
    ],
    "criteria_failed": [],
    "evidence_paths": [
      ".phase_control/evidence/<phase_id>_attempt_<n>.json"
    ],
    "residual_risks": ["none"],
    "re_verification_conclusion": "Independent verification confirms all criteria met",
    "independently_verified_files": ["list of files verified"],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  }
}
```

See `docs/HTE_PROTOCOL.md` §2 for minimal PASS verdict requirements.

## Notes

- Default to skepticism, not trust
- Evidence must support conclusions
- Don't pass on "probably fine"
- Don't fail on trivial issues
- BLOCK when uncertain
- Document reasoning clearly
