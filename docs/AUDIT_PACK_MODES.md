# Audit Pack Modes

> **当前版本**: v2.0（v1.9.0 内容保留为历史参考）

## Overview

Audit Pack is a structured verification output that produces a Markdown report. It supports four modes of increasing intensity.

## Modes

| Mode | Intensity | Scope |
|------|-----------|-------|
| `core` | Minimum | Gate and protocol related tests |
| `delta` | Targeted | Minimal verification based on changed files |
| `dogfood` | High | Full E2E, eval harness, protocol lint, release gate status |
| `full` | Maximum | All core tests + E2E + release gate + doc checks |

### core

Runs the minimum set of checks to verify gate and protocol integrity:

- Eval Harness
- Protocol Lint (release mode)
- phase_gate.sh exists
- hmte-final-check.sh exists
- hmte-release-gate.sh exists
- HTE_PROTOCOL.md exists
- SKILL.md exists

### delta

Runs targeted checks based on changed files:

- Always runs Eval Harness
- If docs/ changed: checks docs directory structure
- If scripts/ changed: checks scripts directory
- If evals/ changed: checks eval cases directory
- If protocol files changed: runs Protocol Lint
- If no changed files specified: runs core subset

Requires `--changed-files` argument with comma-separated file list.

### dogfood

Runs the full dogfood verification suite:

- Eval Harness
- Protocol Lint (release mode)
- Final Check (release mode)
- All E2E tests
- Release Gate status

### full

Maximum intensity verification:

- All core checks
- All E2E tests
- Final Check (release mode)
- Release Gate status
- Dogfood Checklist existence
- Release Gate Protocol doc existence
- Audit Pack Modes doc existence

## Usage

```bash
# Core mode
bash scripts/hmte-audit-pack.sh --mode core

# Delta mode with changed files
bash scripts/hmte-audit-pack.sh --mode delta --changed-files "README.md,src/foo.sh"

# Dogfood mode
bash scripts/hmte-audit-pack.sh --mode dogfood

# Full mode
bash scripts/hmte-audit-pack.sh --mode full

# Invalid mode (must FAIL)
bash scripts/hmte-audit-pack.sh --mode invalid
```

## Output

- Markdown report written to `.phase_control/audits/audit_{mode}_{timestamp}.md`
- Console summary with pass/fail counts
- Exit code 0 on success, 1 on failure

## Fail-Closed Rules

- Invalid mode MUST FAIL (exit 1)
- Missing `--mode` MUST FAIL (exit 1)
- Any check failure in any mode is reported in the audit report
- The audit pack generator does NOT auto-fix issues

## Artifact Storage

- All artifacts are stored in `.phase_control/audits/`
- This directory MUST NOT be committed to Git
- `.phase_control/` is already in `.gitignore`

## What Audit Pack Is NOT

- Not a new Agent
- Not a CI/CD pipeline
- Not a dashboard
- Not an auto-fix tool
- Not a replacement for external audit
