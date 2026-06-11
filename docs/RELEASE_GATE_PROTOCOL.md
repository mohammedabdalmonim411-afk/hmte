# Release Gate Protocol

> **当前版本**: v2.0（v1.9.0 内容保留为历史参考）

## Overview

Release Gate is an **outer gate**, not a new Agent. It has two modes:

- `audit` (default): checks whether the project has met all internal quality criteria and is safe to submit to external audit.
- `release`: checks whether the project is allowed to publish release/GitHub artifacts after external audit.

The release gate does not create, replace, or fabricate an external audit receipt.

## Three-Agent Core

Release Gate does NOT introduce a new Agent. The three core Agents remain:

- **Leader** — plans, delegates, coordinates
- **Worker** — executes tasks, produces evidence
- **Verifier** — independently reviews evidence

Release Gate is a gate, like `phase_gate` and `final-check`.

## Gate Checks

The release gate performs the following checks:

| # | Check | P0/P1 | Fail Condition |
|---|-------|--------|----------------|
| 1 | Eval Harness | P0 | Any eval case fails |
| 2 | Protocol Lint | P1 | Structural violations (beyond missing session files) |
| 3 | Final Check | P1 | File protocol integrity failures (beyond missing session) |
| 4 | Dogfood Audit Pack | P1 | No dogfood audit pack found |
| 5 | External Audit Receipt | Info in `audit`; P1 in `release` | Missing receipt does not block external-audit readiness, but blocks strict release mode |
| 6 | .phase_control in Git | P0 | .phase_control/ files staged in git |
| 7 | Sensitive Files in Git | P0 | test_results.log, .tar.gz, private_validation/ staged |

## Modes

| Mode | Command | Success Verdict | Receipt Requirement |
|------|---------|-----------------|---------------------|
| `audit` | `bash scripts/hmte-release-gate.sh` | `READY_FOR_EXTERNAL_AUDIT` | Reported as informational |
| `release` | `bash scripts/hmte-release-gate.sh --mode release` | `READY_FOR_RELEASE` | Required and must prove PASS with open P0/P1 = 0; missing or invalid receipt is P1 |

## External Audit Receipt Format

Strict release mode accepts a real external audit receipt at one of these paths:

- `.phase_control/external_audit_receipt.json`
- `EXTERNAL_AUDIT_RECEIPT.md`

The receipt must state a PASS-like `result`, `status`, `verdict`, or `external_audit_result`, and must state open P0 and open P1 counts of `0`.

Example JSON shape:

```json
{
  "result": "PASS",
  "open_p0": 0,
  "open_p1": 0
}
```

Example Markdown shape:

```markdown
Result: PASS
Open P0: 0
Open P1: 0
```

These examples are templates only. Do not create either receipt file unless an actual external audit has completed and the values are copied from that audit result.

### Receipt as a Release Artifact (not a source file)

`EXTERNAL_AUDIT_RECEIPT.md` matches the `.gitignore` rule `*_AUDIT*.md`, so it is intentionally **not committed to source control**. It is treated as a release artifact, not a tracked source file:

- The release gate reads it directly from the working tree at release time.
- The `ai-all` audit pack embeds the receipt verbatim (`## File: \`EXTERNAL_AUDIT_RECEIPT.md\``), so external auditors receive its full content inside the pack.
- Release notes must list the receipt as a release artifact accompanying the published build, not as part of the repository source tree.

This keeps the change minimal: no rename and no `.gitignore` exception is required. If a future policy decides the receipt must be tracked in git, rename it to a non-ignored name (e.g. `EXTERNAL_REVIEW_RECEIPT.md`) or add a `.gitignore` exception, and keep the release gate's recognized paths in sync.

## Verdict Semantics

| Verdict | Meaning | Exit Code |
|---------|---------|-----------|
| PASS | All required checks for the selected mode passed | 0 |
| FAIL | P0 or P1 issues found, cannot proceed | 1 |
| PENDING | Reserved for future manual-review gates | 2 |

### Critical Rules

- **P0 > 0 → MUST FAIL**: Any P0 issue blocks all further progress.
- **P1 > 0 → MUST FAIL**: Any P1 issue blocks release.
- **No external audit receipt in `audit` mode → PASS with warning**: Missing receipt does not block `READY_FOR_EXTERNAL_AUDIT`, but release/GitHub publishing remains blocked.
- **No external audit receipt in `release` mode → MUST FAIL**: Strict release mode cannot output `READY_FOR_RELEASE` until a valid receipt exists.
- **Invalid external audit receipt in `release` mode → MUST FAIL**: A receipt must state a PASS-like result and open P0/P1 counts of 0.
- **Release gate does NOT auto-fix**: It only reports status.
- **Release gate does NOT connect to CI/CD**: It is a manual gate.
- **Release gate does NOT produce a dashboard**: It outputs text.

## Usage

```bash
bash scripts/hmte-release-gate.sh
bash scripts/hmte-release-gate.sh --mode audit
bash scripts/hmte-release-gate.sh --mode release
bash scripts/hmte-release-gate.sh --project-root /path/to/project
```

## Relationship to Other Gates

```
phase_gate (per-phase) → final-check (post-phase) → release gate (pre-release)
```

- `phase_gate`: Checks a single phase's evidence chain.
- `final-check`: Checks the entire project's file protocol integrity.
- `release gate` (`audit` mode): Checks whether the project is ready for external audit.
- `release gate` (`release` mode): Checks whether external-audit evidence is present and release/GitHub publishing is allowed.

Each gate is independent. Failing an earlier gate should prevent reaching a later one, but the release gate re-validates everything.

## What Release Gate Is NOT

- Not a new Agent
- Not a CI/CD pipeline
- Not a dashboard
- Not an auto-fix tool
- Not a replacement for external audit
