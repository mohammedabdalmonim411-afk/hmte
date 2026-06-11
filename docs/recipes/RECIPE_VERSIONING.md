# Recipe Versioning

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Status**: Active  

---

## Overview

Recipe Versioning 定义了 TriAgentFlow / TAF workflow recipes 的版本管理规则，确保 recipe 的向后兼容性、废弃管理和演进路径。

---

## Required Fields

所有 recipe 必须包含以下字段：

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| Version | String | Yes | Recipe version (e.g., "2.0") |
| Compatible with: TriAgentFlow / TAF v2.0+") |
| Deprecated | Boolean | Yes | Is this recipe deprecated? |
| Supersedes | String | Yes | Previous recipe version (or "None") |
| Category | String | Yes | Recipe category |
| Risk Level | String | Yes | P0/P1/P2 risk level |
| Plan Items Required | Array | Yes | Required plan item types |

---

## Version Format

Recipe version 遵循以下格式：

```
<major>.<minor>
```

**Major version** changes:
- Breaking changes to recipe structure
- Incompatible with previous versions
- Requires recipe rewrite

**Minor version** changes:
- Backward compatible changes
- Additional phases or steps
- Clarifications or improvements

---

## Deprecation Policy

### Marking as Deprecated

Recipe 标记为废弃时：

```markdown
**Deprecated**: Yes  
**Supersedes**: v1.0  
**Superseded by**: recipe-new-name.md  
**Deprecation Reason**: Replaced by new recipe with improved plan-grounded structure  
**Removal Date**: 2026-12-31  
```

### Deprecated Recipe Rules

1. **不能被 composition 引用** — `hmte-recipe-compose.sh` 必须拒绝 deprecated recipes
2. **必须有 superseded_by** — 指向替代 recipe
3. **必须有 removal_date** — 计划移除日期
4. **必须保留至少 3 个月** — 给用户迁移时间

---

## Supersedes Chain

Recipe 必须记录 supersedes 关系：

```
recipe-schema-change.md v2.0
  ↓ supersedes
recipe-schema-change.md v1.0
  ↓ supersedes
None (initial version)
```

---

## Compatibility Declaration

### Compatible with TAF Versions

Recipe 必须声明兼容的 TAF 版本：

| Declaration | Meaning |
|-------------|---------|
| "TAF v2.0+" | Compatible with v2.0 and later |
| "TAF v2.0 only" | Only compatible with v2.0 |
| "TAF v1.9-v2.0" | Compatible with v1.9 and v2.0 |

### Backward Compatibility

Recipe 必须保持向后兼容，除非有 major version bump。

**向后兼容的变更**：
- 添加可选 phase
- 添加可选 step
- 改进文档
- 添加更多 negative tests

**不向后兼容的变更**（需要 major version bump）：
- 删除 required phase
- 修改 plan item requirements
- 修改 gate configuration requirements

---

## Recipe Composition Rules

### Deprecated Recipe Check

`hmte-recipe-compose.sh` 必须检查：

```bash
# Pseudo code
if recipe.deprecated == true:
    echo "ERROR: Recipe ${recipe_name} is deprecated"
    echo "Use ${recipe.superseded_by} instead"
    exit 1
```

### Version Compatibility Check

```bash
# Pseudo code
if recipe.compatible_with not matches current_hte_version:
    echo "WARNING: Recipe ${recipe_name} may not be compatible"
    echo "Recipe requires: ${recipe.compatible_with}"
    echo "Current TAF version: ${current_hte_version}"
    # Proceed with warning, or fail if strict mode
```

---

## Recipe Migration Guide

### Migrating from v1.0 to v2.0

1. **Add plan_ref to all phases**
   ```markdown
   **Plan Items**: [S-xxx, AC-xxx, T-xxx]
   ```

2. **Add plan item requirements table**
   ```markdown
   | Plan Item Type | Minimum Count | Example IDs |
   |----------------|---------------|-------------|
   | Scope Item | 1 | S-001 |
   ```

3. **Add evidence requirements**
   ```markdown
   **Evidence Required**:
   - `changed_files`: File paths
   - `command_logs`: Command execution logs
   - `tests_run`: Test names
   ```

4. **Update gate configuration**
   ```markdown
   **Gate Config**: `docs/intensity-configs/gate-strict.json`
   ```

5. **Update version fields**
   ```markdown
   **Version**: 2.0
   **Supersedes**: v1.0
   **Compatible with**: TriAgentFlow / TAF v2.0+
   ```

---

## Recipe Registry

### Active Recipes (v2.0)

| Recipe | Version | Risk Level | Status |
|--------|---------|------------|--------|
| recipe-schema-change.md | 2.0 | P0 | Active |
| recipe-gate-enhancement.md | 2.0 | P0 | Active |
| recipe-documentation-update.md | 2.0 | P2 | Active |

### Deprecated Recipes

| Recipe | Deprecated | Superseded By | Removal Date |
|--------|------------|---------------|--------------|
| (none yet) | - | - | - |

---

## Verification

### Recipe Versioning Checklist

- [ ] Version field present
- [ ] Compatible with field present
- [ ] Deprecated field present
- [ ] Supersedes field present
- [ ] Category field present
- [ ] Risk Level field present
- [ ] Plan Items Required field present
- [ ] If deprecated, superseded_by present
- [ ] If deprecated, removal_date present
- [ ] Version format valid (major.minor)

---

## Example: Complete Recipe Header

```markdown
# Workflow Recipe: Schema Change

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Deprecated**: No  
**Supersedes**: v1.0  
**Category**: Core Protocol  
**Risk Level**: P0  
**Plan Items Required**: ["S-xxx", "AC-xxx", "T-xxx", "NT-xxx"]  

---
```

---

**Last Updated**: 2026-06-10  
**Maintainer**: TAF Core Team
