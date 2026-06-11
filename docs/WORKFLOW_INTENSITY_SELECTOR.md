# TriAgentFlow / TAF Rule-first Workflow Intensity Selector v2.0

**Version**: 2.0  
**Status**: Implemented  
**Related**: HTE_v2.0_PROJECT_PLAN.md P1-1  

---

## 1. Overview

Rule-first Workflow Intensity Selector 根据任务特征和文件变更模式，推荐合适的治理强度级别（direct / standard / strict / parallel_safe / release / dogfood）。

核心原则：**Rule-first, AI advisory optional**。

---

## 2. Intensity Levels

| Level | Use Case | Gate Checks |
|-------|----------|-------------|
| `direct` | Typo, comments, non-core docs | Minimal (no evidence required for trivial changes) |
| `standard` | Most development tasks | Evidence + Verdict + Command log |
| `strict` | Core protocol, schema, gate files | Evidence + Verdict + Command log + Negative tests + Protocol lint |
| `parallel_safe` | Phase-internal parallelism | Standard checks + Parallel verdict aggregation |
| `release` | Release preparation | Strict checks + Release gate + External audit receipt |
| `dogfood` | Full dogfood validation | Release checks + Dogfood checklist + Planted lazy-path cases |

---

## 3. Rule Table

### 3.1 Strict Rules (High Priority)

| Pattern | Intensity | Reason |
|---------|-----------|--------|
| `phase_gate.sh` | `strict` | Core gate logic |
| `hmte-final-check.sh` | `strict` | Final check logic |
| `HTE_PROTOCOL.md` | `strict` | Protocol definition |
| `*-schema.json` | `strict` | Schema definition |
| `evidence-schema.json` | `strict` | Evidence structure |
| `verdict-schema.json` | `strict` | Verdict structure |
| `scripts/hmte-*gate*.sh` | `strict` | Gate scripts |
| `src/skills/hmte/*` | `strict` | TAF skill files under legacy path |

### 3.2 Standard Rules (Medium Priority)

| Pattern | Intensity | Reason |
|---------|-----------|--------|
| `scripts/hmte-*.sh` | `standard` | TAF utility scripts with legacy prefix |
| `*.py` | `standard` | Source code |
| `*.js` | `standard` | Source code |
| `*.sh` | `standard` | Shell scripts |
| `src/agents/*.md` | `standard` | Agent definitions |

### 3.3 Direct Rules (Low Priority)

| Pattern | Intensity | Reason |
|---------|-----------|--------|
| `README.md` | `direct` | Non-core documentation |
| `CONTRIBUTING.md` | `direct` | Non-core documentation |
| `docs/*.md` (non-architecture) | `direct` | General documentation |
| Task desc: "typo" | `direct` | Trivial fix |
| Task desc: "comment" | `direct` | Trivial fix |
| Task desc: "formatting" | `direct` | Trivial fix |

**Exception**: Direct mode is **forbidden** for:
- `scripts/*`
- `src/*`
- `*.py`, `*.js`, `*.sh`
- Architecture docs (HTE_PROTOCOL, PLAN_CONTRACT, etc.)

---

## 4. Rule-first Algorithm

```python
def select_intensity(task_desc, changed_files):
    # Rule 1: Core protocol files → strict
    if matches_pattern(changed_files, STRICT_PATTERNS):
        return "strict", "high"
    
    # Rule 2: TAF legacy hmte scripts → standard
    if matches_pattern(changed_files, STANDARD_PATTERNS):
        return "standard", "medium"
    
    # Rule 3: Documentation only (non-architecture) → direct
    if matches_pattern(changed_files, DIRECT_PATTERNS):
        if forbidden_for_direct(changed_files):
            return "standard", "high"  # Upgrade to standard
        return "direct", "medium"
    
    # Rule 4: Task description keywords → direct
    if matches_keywords(task_desc, ["typo", "comment", "formatting"]):
        if forbidden_for_direct(changed_files):
            return "standard", "high"  # Upgrade to standard
        return "direct", "low"
    
    # Default: standard
    return "standard", "medium"
```

---

## 5. AI Advisory Mode (P1 Optional)

AI Advisory Mode 是**可选增强**，不是硬依赖。

### 5.1 Activation

```bash
bash scripts/hmte-workflow-selector.sh \
  --task-description "Modify phase_gate.sh logic" \
  --changed-files "scripts/phase_gate.sh" \
  --with-ai
```

### 5.2 Behavior

- AI 分析任务描述和文件变更，给出推荐
- 如果 AI 分析失败，自动回退到 Rule Mode
- AI 推荐仅作为参考，不参与 gate 决策
- AI 失败不阻塞 release

### 5.3 Fallback

```
Rule Mode (P0, 默认)
  ↓ if --with-ai
AI Advisory Mode (P1, 可选)
  ↓ if AI fails
Fallback to Rule Mode (自动)
```

---

## 6. Output Format

```json
{
  "task_description": "Fix typo in README",
  "changed_files": "README.md",
  "rule_mode": {
    "recommended_intensity": "direct",
    "reason": "Documentation-only change (non-architecture)",
    "confidence": "medium"
  },
  "ai_advisory_mode": {
    "enabled": false,
    "recommendation": "",
    "confidence": "",
    "reasoning": ""
  },
  "final_recommendation": "direct"
}
```

---

## 7. Integration with phase_gate

phase_gate 可以读取 selector 推荐，但**不强制要求**。

```bash
# Optional: Get recommendation
bash scripts/hmte-workflow-selector.sh \
  --task-description "$TASK_DESC" \
  --changed-files "$CHANGED_FILES" \
  --output intensity-recommendation.json

# phase_gate can optionally check recommendation
# but defaults to standard if not provided
bash scripts/phase_gate.sh phase_1
```

---

## 8. Validation

### 8.1 Rule Accuracy Test

给定 fixture set，验证推荐结果：

| Input | Expected | Confidence |
|-------|----------|-----------|
| `phase_gate.sh` | `strict` | high |
| `hmte-plan-lock.sh` | `standard` | medium |
| `README.md` (typo) | `direct` | medium |
| `src/agents/verifier.md` | `standard` | medium |
| `evidence-schema.json` | `strict` | high |

### 8.2 Forbidden Direct Test

| Input | Expected | Reason |
|-------|----------|--------|
| `scripts/test.sh` (typo) | `standard` | Direct forbidden for scripts |
| `src/main.py` (comment) | `standard` | Direct forbidden for code |

---

## 9. P1 Status

Selector 是 **P1 能力**，不阻塞 v2.0 核心闭环。

- Rule Mode 是 P0 基础
- AI Advisory Mode 是 P1 增强
- Selector 推荐是可选的，phase_gate 可以独立运行

---

## 10. Usage Examples

### Example 1: Core Protocol File

```bash
bash scripts/hmte-workflow-selector.sh \
  --task-description "Add plan coverage check to phase_gate" \
  --changed-files "scripts/phase_gate.sh"

# Output: strict (Core protocol file detected)
```

### Example 2: Documentation Fix

```bash
bash scripts/hmte-workflow-selector.sh \
  --task-description "Fix typo in README" \
  --changed-files "README.md"

# Output: direct (Documentation-only change)
```

### Example 3: Forbidden Direct

```bash
bash scripts/hmte-workflow-selector.sh \
  --task-description "Fix typo in hmte-plan-lock.sh" \
  --changed-files "scripts/hmte-plan-lock.sh"

# Output: standard (Direct forbidden for scripts, upgrading to standard)
```

### Example 4: AI Advisory Mode

```bash
bash scripts/hmte-workflow-selector.sh \
  --task-description "Refactor evidence validation logic" \
  --changed-files "scripts/hmte-check-fidelity.sh" \
  --with-ai

# Output: standard (Rule Mode) + AI advisory (if available)
```

---

## 11. AI Boundary

| AI 可以 | AI 不可以 |
|---------|----------|
| 提供推荐（advisory） | 修改 rule table |
| 分析任务复杂度 | 绕过 phase_gate |
| 解释推荐理由 | 降低门禁强度 |
| 失败时自动回退 | 阻塞 release（失败时） |

---

## 12. Future Enhancements (v2.1+)

- AI 生成 recipe（基于任务描述）
- 历史数据分析（提升 rule table 准确率）
- Multi-language support（支持非英文任务描述）

---

**Version**: 2.0  
**Last Updated**: 2026-06-10  
**Status**: Implemented
