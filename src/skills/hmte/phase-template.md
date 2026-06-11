# Phase Template

Use this template when defining phases in `.phase_control/phases.json`.

## Minimal Valid Example

```json
{
  "project_name": "Example Project",
  "phases": [
    {
      "phase_id": "phase_a",
      "goal": "Clear, measurable goal",
      "acceptance_criteria": [
        "Criterion 1",
        "Criterion 2"
      ]
    },
    {
      "phase_id": "phase_b",
      "goal": "Another clear goal",
      "acceptance_criteria": [
        "Criterion 1",
        "Criterion 2",
        "Criterion 3"
      ]
    }
  ]
}
```

## Required Fields (Validator Enforced)

| Field | Type | Description |
|-------|------|-------------|
| `phase_id` | string | Unique identifier (e.g., `phase_a`, `phase_b`) |
| `goal` | string | Clear statement of what this phase aims to achieve |
| `acceptance_criteria` | array[string] | List of criteria that must be met for phase to pass |

These three fields are **mandatory**. The validator (`hmte-validate-phases.sh`, `phase_gate.sh`) will reject phases missing any of them.

## Optional Planning Fields

The following fields are useful for planning but **not required by the validator**:

| Field | Type | Description |
|-------|------|-------------|
| `inputs` | array[string] | Required inputs for this phase |
| `outputs` | array[string] | Expected outputs from this phase |
| `required_evidence` | array[string] | Types of evidence to collect |
| `timeout_soft` | integer | Soft timeout in seconds (warning, continues) |
| `timeout_hard` | integer | Hard timeout in seconds (terminated) |
| `max_retries` | integer | Maximum retry attempts (default: 2) |
| `escalation_rule` | string | When to escalate to Leader or human |
| `priority` | string | Phase priority (e.g., "P0", "P1") |
| `context` | object | Additional context for Worker |

## Full Example with Optional Fields

```json
{
  "project_name": "User Auth Module",
  "phases": [
    {
      "phase_id": "phase_setup",
      "goal": "Initialize project structure and install dependencies",
      "acceptance_criteria": [
        "package.json exists",
        "Dependencies installed successfully"
      ],
      "inputs": ["User requirements", "Project codebase"],
      "outputs": ["Initialized project", "Installed dependencies"],
      "required_evidence": ["changed_files", "commands_run"],
      "timeout_soft": 600,
      "timeout_hard": 1200,
      "max_retries": 2,
      "escalation_rule": "连续2次FAIL升级到Leader重规划"
    },
    {
      "phase_id": "phase_impl",
      "goal": "Implement user authentication API with JWT and bcrypt",
      "acceptance_criteria": [
        "JWT generation works",
        "bcrypt hashing works",
        "API returns correct responses",
        "All tests pass"
      ],
      "inputs": ["Design document", "API specification"],
      "outputs": ["Login API code", "Unit tests", "Integration tests"],
      "required_evidence": ["changed_files", "commands_run", "test_results"],
      "timeout_soft": 900,
      "timeout_hard": 1800,
      "max_retries": 2,
      "escalation_rule": "连续2次FAIL升级"
    },
    {
      "phase_id": "phase_test",
      "goal": "Write and run unit tests with coverage > 80%",
      "acceptance_criteria": [
        "All tests pass",
        "Coverage > 80%"
      ],
      "inputs": ["Implementation code"],
      "outputs": ["Test suite", "Coverage report"],
      "required_evidence": ["test_results", "artifact_paths"],
      "timeout_soft": 600,
      "timeout_hard": 1200,
      "max_retries": 1,
      "escalation_rule": "任何FAIL都升级"
    }
  ]
}
```

## Parallel Phase Example

For phases that can run in parallel (`execution_mode: parallel_safe`):

```json
{
  "project_name": "Feature Implementation",
  "phases": [
    {
      "phase_id": "phase_impl",
      "goal": "Implement feature X with isolated sub-tasks",
      "execution_mode": "parallel_safe",
      "parallel_workers": [
        {
          "worker_id": "impl-core",
          "scope": "Implement core logic",
          "forbidden_paths": ["src/api/**", "tests/api/**"]
        },
        {
          "worker_id": "impl-api",
          "scope": "Implement API layer",
          "forbidden_paths": ["src/core/**", "tests/core/**"]
        }
      ],
      "acceptance_criteria": [
        "Both sub-tasks complete",
        "No file overlap between workers",
        "All tests pass"
      ]
    }
  ]
}
```

## Field Descriptions

### phase_id
- Unique identifier for the phase
- Format: `^[A-Za-z0-9_-]+$` (letters, numbers, underscores, hyphens)
- Used in file names and logs
- **v1.8 canonical field** (replaces deprecated `id` / `name`)

### goal
- Clear statement of what this phase aims to achieve
- Should be measurable and verifiable
- Example: "Implement user login API with JWT authentication"
- **v1.8 canonical field** (replaces deprecated `objective` / `description`)

### acceptance_criteria
- List of criteria that must be met for phase to pass
- Should be specific and testable
- **Must be an array** (v1.8 requirement)
- Example:
  - "All unit tests pass"
  - "Code coverage > 80%"
  - "API returns JWT token on successful login"

### inputs (optional)
- List of required inputs for this phase
- Can be files, documents, or information
- Example: ["User requirements", "API design doc"]

### outputs (optional)
- List of expected outputs from this phase
- Should be concrete and verifiable
- Example: ["Login API code", "Unit tests", "API documentation"]

### required_evidence (optional)
- Types of evidence that must be collected
- Common types:
  - `changed_files`: List of modified files
  - `commands_run`: Commands executed
  - `test_results`: Test execution results
  - `build_results`: Build success/failure
  - `screenshots`: UI screenshots (frontend)
  - `console_errors`: Browser errors (frontend)
  - `lint_results`: Linting results

### timeout_soft (optional)
- Soft timeout in seconds
- Worker receives warning but continues
- Default: 600 (10 minutes)

### timeout_hard (optional)
- Hard timeout in seconds
- Worker is forcibly terminated
- Default: 1200 (20 minutes)

### max_retries (optional)
- Maximum number of retry attempts
- After this, phase escalates to Leader
- Default: 2

### escalation_rule (optional)
- Rule for when to escalate to Leader or human
- Example: "连续2次FAIL升级到Leader重规划"

## Tips

1. **Keep phases focused**: Each phase should have a single, clear objective
2. **Make criteria testable**: Acceptance criteria should be verifiable
3. **Be realistic with timeouts**: Consider complexity when setting timeouts
4. **Require appropriate evidence**: Match evidence types to phase type
5. **Plan for failure**: Set reasonable retry limits and escalation rules
