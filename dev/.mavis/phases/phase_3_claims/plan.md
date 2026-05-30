# Phase 3: hmte-claims.sh

## Objective
Create capability declaration script that honestly states HTE's current boundaries and capabilities.

## Scope
- Create `scripts/hmte-claims.sh`
- Output structured capability declarations
- Clarify what HTE is and is not

## Success Criteria
- Script executable and outputs correct format
- All capability claims are accurate
- No over-promising of features

## Output Format
```
workflow_mode: FILE_PROTOCOL
agent_runtime: EXTERNAL_HERMES_REQUIRED
delegation_proof: INTENT_ONLY
observed_delegation: UNAVAILABLE
phase_gate: ENABLED
final_audit: MANUAL
protocol_lint: ENABLED
team_rules: ENABLED
```

## Constraints
- Do NOT claim HTE is a complete standalone Agent Runtime
- Do NOT claim OBSERVED delegation is currently available
- Must clarify that real Worker/Verifier execution depends on Hermes delegate_task or external Agent environment
