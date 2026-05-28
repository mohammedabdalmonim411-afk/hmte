# Team Engine Policy

This project uses the HTE for structured development.

## Core Rules (MANDATORY - NOT OPTIONAL)

1. **All complex tasks MUST use Team Engine**
   - MUST write phases to `.phase_control/phases.yaml` first
   - MUST execute through master-planner → phase-executor → verifier flow
   - MUST NOT bypass the verification step

2. **Phase Gate Enforcement (MANDATORY)**
   - No phase proceeds without verifier PASS
   - Evidence bundle REQUIRED for every phase
   - State machine MUST be maintained

3. **Role Boundaries (STRICT)**
   - ONLY master-planner modifies `.phase_control/state.json`
   - phase-executor produces implementation and evidence
   - verifier ONLY audits, does NOT modify code
   - Each role MUST stay in its lane

4. **Evidence Requirements (MANDATORY)**
   - Every phase MUST produce evidence bundle
   - Evidence MUST match required_evidence in phase spec
   - No subjective "looks good" - evidence-based only

5. **Retry and Escalation (MANDATORY)**
   - FAIL → rework (up to max_retries)
   - Consecutive FAILs → escalate to Leader
   - BLOCK → immediate escalation
   - MUST preserve all evidence and verdicts

6. **Frontend/UI Changes (MANDATORY)**
   - MUST require browser evidence when possible
   - Screenshots, console logs, network traces
   - If no browser available, MUST document limitation

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

### Hook Registration (Manual Setup Required)

> **⚠️ Important**: Hermes does not automatically register hooks from `.claude/hooks/`. You must manually configure them in your Hermes profile.

The project includes three safety hooks:
- `pretool_guard.sh` - Blocks dangerous commands (rm -rf, dd, etc.)
- `stop_gate.sh` - Prevents premature session termination
- `task_naming.sh` - Enforces task naming conventions

**To enable hooks in Hermes:**

1. Copy hooks to your Hermes profile:
```bash
cp .claude/hooks/*.sh ~/.hermes/profiles/default/hooks/
```

2. Configure in your Hermes profile settings (if supported), or

3. Manually invoke hooks in agent prompts:
```bash
# Before executing commands, run:
bash .claude/hooks/pretool_guard.sh "command_to_check"

# Before stopping session, run:
bash .claude/hooks/stop_gate.sh
```

**Note**: Hook integration depends on your Hermes setup. Consult Hermes documentation for the correct hook registration method for your version.

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
