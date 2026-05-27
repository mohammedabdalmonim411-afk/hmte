# Team Engine Policy

This project uses the HMTE for structured development.

## Core Rules

1. **All complex tasks must use Team Engine**
   - Write phases to `.phase_control/phases.yaml` first
   - Execute through master-planner → phase-executor → verifier flow
   - Do not bypass the verification step

2. **Phase Gate Enforcement**
   - No phase proceeds without verifier PASS
   - Evidence bundle required for every phase
   - State machine must be maintained

3. **Role Boundaries**
   - Only master-planner modifies `.phase_control/state.json`
   - phase-executor produces implementation and evidence
   - verifier only audits, does not modify code
   - Each role stays in its lane

4. **Evidence Requirements**
   - Every phase must produce evidence bundle
   - Evidence must match required_evidence in phase spec
   - No subjective "looks good" - evidence-based only

5. **Retry and Escalation**
   - FAIL → rework (up to max_retries)
   - Consecutive FAILs → escalate to Leader
   - BLOCK → immediate escalation
   - Preserve all evidence and verdicts

6. **Frontend/UI Changes**
   - Require browser evidence when possible
   - Screenshots, console logs, network traces
   - If no browser available, document limitation

## File Ownership

- `.phase_control/state.json` - master-planner only
- `.phase_control/phases.yaml` - master-planner only
- `.phase_control/evidence/*.json` - phase-executor only
- `.phase_control/verdicts/*.txt` - verifier only

## Workflow

```
User Request
  ↓
master-planner: Generate phases.yaml
  ↓
For each phase:
  master-planner: Dispatch to phase-executor
  phase-executor: Execute + produce evidence
  master-planner: Dispatch to verifier
  verifier: Audit + output verdict
  master-planner: PASS→next | FAIL→rework | BLOCK→escalate
```

## Safety

- Hooks enforce dangerous command blocking
- Stop gate prevents incomplete termination
- Worktree isolation for phase-executor
- Read-only by default for verifier

## Models

- master-planner: opus (or sonnet if constrained)
- phase-executor: sonnet
- verifier: opus (or sonnet with more tests)

## When NOT to Use Team Engine

- Simple one-file edits
- Trivial bug fixes
- Documentation updates
- Exploratory research

Use Team Engine for:
- Multi-phase implementations
- Features requiring verification
- Changes with quality gates
- Complex refactoring
