# Phase Template

Use this template when defining phases in `.phase_control/phases.json`.

## Phase Definition

```yaml
- id: phase_<letter>
  name: "Phase Name"
  objective: "Clear, measurable objective"
  inputs:
    - "Input 1"
    - "Input 2"
  outputs:
    - "Output 1"
    - "Output 2"
  acceptance_criteria:
    - "Criterion 1"
    - "Criterion 2"
    - "Criterion 3"
  required_evidence:
    - "changed_files"
    - "test_results"
    - "build_results"
  timeout_soft: 600
  timeout_hard: 1200
  max_retries: 2
  escalation_rule: "连续2次FAIL升级到Leader重规划"
```

## Field Descriptions

### id
- Unique identifier for the phase
- Format: `phase_<letter>` (e.g., phase_a, phase_b)
- Used in file names and logs

### name
- Human-readable phase name
- Should be descriptive and concise

### objective
- Clear statement of what this phase aims to achieve
- Should be measurable and verifiable
- Example: "Implement user login API with JWT authentication"

### inputs
- List of required inputs for this phase
- Can be files, documents, or information
- Example: ["User requirements", "API design doc"]

### outputs
- List of expected outputs from this phase
- Should be concrete and verifiable
- Example: ["Login API code", "Unit tests", "API documentation"]

### acceptance_criteria
- List of criteria that must be met for phase to pass
- Should be specific and testable
- Example:
  - "All unit tests pass"
  - "Code coverage > 80%"
  - "API returns JWT token on successful login"

### required_evidence
- Types of evidence that must be collected
- Common types:
  - `changed_files`: List of modified files
  - `commands_run`: Commands executed
  - `test_results`: Test execution results
  - `build_results`: Build success/failure
  - `screenshots`: UI screenshots (frontend)
  - `console_errors`: Browser errors (frontend)
  - `lint_results`: Linting results

### timeout_soft
- Soft timeout in seconds
- Worker receives warning but continues
- Default: 600 (10 minutes)

### timeout_hard
- Hard timeout in seconds
- Worker is forcibly terminated
- Default: 1200 (20 minutes)

### max_retries
- Maximum number of retry attempts
- After this, phase escalates to Leader
- Default: 2

### escalation_rule
- Rule for when to escalate to Leader or human
- Example: "连续2次FAIL升级到Leader重规划"

## Example Phases

### Phase A: Requirements Analysis

```yaml
- id: phase_a
  name: "Requirements Analysis and Design"
  objective: "Understand requirements and create design document"
  inputs:
    - "User requirements"
    - "Project codebase"
  outputs:
    - "Requirements document"
    - "Design document"
    - "API specification"
  acceptance_criteria:
    - "Requirements are clear and unambiguous"
    - "Design covers all requirements"
    - "API spec is complete"
  required_evidence:
    - "changed_files"
    - "artifact_paths"
  timeout_soft: 600
  timeout_hard: 1200
  max_retries: 2
  escalation_rule: "连续2次FAIL升级"
```

### Phase B: Implementation

```yaml
- id: phase_b
  name: "Backend API Implementation"
  objective: "Implement login API with JWT authentication"
  inputs:
    - "Design document"
    - "API specification"
  outputs:
    - "Login API code"
    - "Unit tests"
    - "Integration tests"
  acceptance_criteria:
    - "API endpoint implemented"
    - "JWT token generation works"
    - "Password hashing with bcrypt"
    - "All tests pass"
    - "Code coverage > 80%"
  required_evidence:
    - "changed_files"
    - "commands_run"
    - "test_results"
    - "build_results"
  timeout_soft: 900
  timeout_hard: 1800
  max_retries: 2
  escalation_rule: "连续2次FAIL升级"
```

### Phase C: Frontend Implementation

```yaml
- id: phase_c
  name: "Login UI Implementation"
  objective: "Implement login form and integrate with API"
  inputs:
    - "Design mockups"
    - "API specification"
  outputs:
    - "Login component"
    - "Form validation"
    - "API integration"
    - "Unit tests"
  acceptance_criteria:
    - "Login form renders correctly"
    - "Form validation works"
    - "API integration successful"
    - "Error handling implemented"
    - "All tests pass"
  required_evidence:
    - "changed_files"
    - "test_results"
    - "screenshots"
    - "console_errors"
  timeout_soft: 900
  timeout_hard: 1800
  max_retries: 2
  escalation_rule: "连续2次FAIL升级"
```

### Phase D: Integration Testing

```yaml
- id: phase_d
  name: "End-to-End Integration Testing"
  objective: "Verify complete login flow works end-to-end"
  inputs:
    - "Backend API"
    - "Frontend UI"
  outputs:
    - "E2E test suite"
    - "Test results"
    - "Bug fixes (if any)"
  acceptance_criteria:
    - "E2E tests cover happy path"
    - "E2E tests cover error cases"
    - "All E2E tests pass"
    - "No console errors"
    - "No network errors"
  required_evidence:
    - "test_results"
    - "screenshots"
    - "console_errors"
    - "network_findings"
  timeout_soft: 600
  timeout_hard: 1200
  max_retries: 2
  escalation_rule: "连续2次FAIL升级"
```

### Phase E: Final Verification

```yaml
- id: phase_e
  name: "Final Verification and Documentation"
  objective: "Verify all requirements met and documentation complete"
  inputs:
    - "All previous phase outputs"
  outputs:
    - "Final verification report"
    - "Updated documentation"
    - "Deployment checklist"
  acceptance_criteria:
    - "All requirements implemented"
    - "All tests pass"
    - "Documentation complete"
    - "No critical bugs"
  required_evidence:
    - "test_results"
    - "artifact_paths"
  timeout_soft: 600
  timeout_hard: 1200
  max_retries: 1
  escalation_rule: "任何FAIL都升级"
```

## Tips

1. **Keep phases focused**: Each phase should have a single, clear objective
2. **Make criteria testable**: Acceptance criteria should be verifiable
3. **Be realistic with timeouts**: Consider complexity when setting timeouts
4. **Require appropriate evidence**: Match evidence types to phase type
5. **Plan for failure**: Set reasonable retry limits and escalation rules
