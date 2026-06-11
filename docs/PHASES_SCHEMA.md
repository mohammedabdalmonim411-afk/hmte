# TriAgentFlow / TAF phases.json Canonical Schema

**Version**: 1.8.0  
**Purpose**: phases.json 的单一权威 schema 参考（Markdown 格式）

---

## Schema Format

This is a **Markdown canonical reference**, not a JSON Schema validator.

`hmte-validate-phases.sh` implements lightweight jq-based checks:
- Required fields presence
- Deprecated field names detection (WARN/FAIL by mode)
- Basic structure validation

For full JSON Schema validation, use external tools (not bundled with TAF).

---

## Canonical Field Names (v1.8+)

### Required Fields

**Project Level**:
- `project_name` (string) — 项目名称

**Phase Level** (array: `phases`):
- `phase_id` (string) — **唯一标识符（canonical name）**
- `goal` (string) — **阶段目标（canonical name）**
- `acceptance_criteria` (array[string]) — 验收标准

### Optional Fields

**Phase Level**:
- `execution_mode` (enum: "sequential" | "parallel_safe") — 执行模式（默认 sequential）
- `parallel_workers` (array) — parallel_safe 时的 worker 定义
  - `worker_id` (string)
  - `scope` (string)
  - `forbidden_paths` (array[string])

---

## Deprecated Field Names (v1.8 removed)

以下字段名已废弃，新文件不应使用：

- ❌ `id` → use `phase_id`
- ❌ `name` → use `phase_id`
- ❌ `objective` → use `goal`
- ❌ `description` → use `goal`

---

## Validation Strategy (v1.8)

**策略**: **canonicalize, do not hard-break**

| 场景 | 行为 |
|------|------|
| `hmte-kickoff.sh` 新生成 | 必须使用 canonical schema (`phase_id` / `goal`) |
| `hmte-validate-phases.sh` 默认 | deprecated fields → **WARN**, exit 0 |
| `HMTE_LINT_MODE=release` | deprecated fields → **FAIL**, exit 1 |
| `orchestrator.py` 读取旧 schema | 应 normalize，不直接崩溃 |

---

## Example: Sequential Phase

```json
{
  "project_name": "My Project",
  "phases": [
    {
      "phase_id": "implement_auth",
      "goal": "实现登录接口",
      "acceptance_criteria": [
        "登录 API 可工作",
        "测试通过"
      ]
    }
  ]
}
```

---

## Example: Parallel Safe Phase

```json
{
  "project_name": "My Project",
  "phases": [
    {
      "phase_id": "implement_modules",
      "goal": "并行实现多个独立模块",
      "execution_mode": "parallel_safe",
      "parallel_workers": [
        {
          "worker_id": "module_a",
          "scope": "实现模块 A",
          "forbidden_paths": ["src/module_b/", "src/module_c/"]
        },
        {
          "worker_id": "module_b",
          "scope": "实现模块 B",
          "forbidden_paths": ["src/module_a/", "src/module_c/"]
        }
      ],
      "acceptance_criteria": [
        "所有模块测试通过",
        "无文件冲突"
      ]
    }
  ]
}
```

---

## Validation Commands

### Validate phases.json

```bash
# 默认模式（WARN on deprecated）
bash scripts/hmte-validate-phases.sh .phase_control/phases.json

# Release 模式（FAIL on deprecated）
HMTE_LINT_MODE=release bash scripts/hmte-validate-phases.sh .phase_control/phases.json
```

### Integrated in Protocol Lint

```bash
HMTE_LINT_MODE=release bash scripts/hmte-lint-protocol.sh
```

---

## Migration Guide

如果你的 phases.json 使用旧字段名：

### Before (deprecated)
```json
{
  "phases": [
    {
      "id": "phase_1",
      "objective": "实现功能",
      "acceptance_criteria": ["完成"]
    }
  ]
}
```

### After (canonical)
```json
{
  "phases": [
    {
      "phase_id": "phase_1",
      "goal": "实现功能",
      "acceptance_criteria": ["完成"]
    }
  ]
}
```

**Note**: `success_criteria` is NOT a supported legacy alias in v1.8 validator. Use `acceptance_criteria` in both old and new schemas.

---

## Backward Compatibility

v1.8 不强制破坏旧 schema：

- 默认模式：deprecated fields → WARN（不阻断）
- release 模式：deprecated fields → FAIL（阻断封版）
- orchestrator：应尽量 normalize 旧 schema

新项目和新 phases.json 应使用 canonical schema。

---

**Document Version**: 1.8.0  
**Last Updated**: 2026-06-03  
**Status**: Authoritative Canonical Reference
