# Workflow Recipe: Documentation Update

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Deprecated**: No  
**Supersedes**: v1.0  
**Category**: Documentation  
**Risk Level**: P2  
**Plan Items Required**: ["S-xxx", "AC-xxx"]  

---

## Overview

Low-risk recipe for documentation-only changes that do not affect protocol behavior, schemas, or gate scripts. Suitable for README updates, design docs, and usage examples.

---

## When to Use

Use this recipe when:
- Updating README.md
- Adding usage examples to docs
- Fixing typos in documentation
- Clarifying existing documentation
- Adding new design documents

Do NOT use for:
- Protocol specification changes
- Schema documentation (use schema-change recipe)
- Gate script documentation (use gate-enhancement recipe)
- Changes that affect behavior

---

## Plan Item Requirements

| Plan Item Type | Minimum Count | Example IDs |
|----------------|---------------|-------------|
| Scope Item | 1 | S-020 |
| Acceptance Criteria | 1+ | AC-020 |
| Required Tests | 0 | N/A |
| Required Negative Tests | 0 | N/A |

---

## Phases

### Phase 1: Documentation Update

**Plan Items**: [S-xxx, AC-xxx]

**Steps**:
1. Update documentation files
2. Verify markdown formatting
3. Check links (internal and external)
4. Review for clarity and accuracy

**Evidence Required**:
- `changed_files`: Documentation file paths
- `command_logs`: Markdown lint, link checker
- `git_diff.txt`: Diff of changes

**Acceptance Criteria**: [AC-xxx]
- Documentation updated
- Markdown valid
- Links working
- No typos

---

### Phase 2: Review & Verification

**Plan Items**: [AC-xxx]

**Steps**:
1. Render documentation (if applicable)
2. Verify examples are correct
3. Check consistency with protocol
4. Verify no sensitive information leaked

**Evidence Required**:
- `review_notes.md`: Review findings
- `rendered_preview.png`: Screenshot (if applicable)
- `consistency_check.md`: Protocol consistency verification

**Acceptance Criteria**: [AC-xxx]
- Documentation renders correctly
- Examples accurate
- Consistent with protocol
- No sensitive data

---

## Gate Configuration

**Recommended Intensity**: direct

**Gate Config**: `docs/intensity-configs/gate-direct.json`

**Required Gate Checks**:
- evidence_required: true
- verdict_required: true
- command_log_required: false (optional for docs)
- negative_tests_required: false

---

## Pitfalls

| Pitfall | Mitigation |
|---------|------------|
| Broken links | Run link checker |
| Inconsistent with protocol | Cross-reference protocol spec |
| Sensitive data leak | Review for paths, usernames |
| Outdated examples | Test examples against current version |

---

## Verification

### Required Tests

- None (documentation-only)

### Required Artifacts

- Updated documentation files
- Markdown lint output
- Link checker output

### Required Command Logs

- Markdown lint
- Link checker (optional)

---

## Success Criteria

- [ ] Documentation updated
- [ ] Markdown valid
- [ ] Links working
- [ ] No sensitive data
- [ ] Consistent with protocol

---

## Example Usage

```bash
# Generate phases.json from this recipe
bash scripts/hmte-recipe-compose.sh \
  --recipe docs/recipes/recipe-documentation-update.md \
  --plan HTE_v2.0_PROJECT_PLAN.md \
  --plan-items "S-020,AC-020" \
  --output .phase_control/phases.json
```

---

**Last Updated**: 2026-06-10  
**Maintainer**: TAF Core Team
