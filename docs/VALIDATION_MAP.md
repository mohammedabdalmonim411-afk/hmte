# TriAgentFlow / TAF Validation Map

**Version**: 1.8.0  
**Purpose**: 定义"改什么，必须验证什么"的通用映射

---

## Overview

Validation Map 明确每种变更类型需要的验证方式。

**"Validation" 不只是 test**：还包括 lint、build、schema check、文档一致性检查、人工审计、grep 检查等。

---

## Change Areas

### 1. Gate / Protocol Scripts

**Files**: `phase_gate.sh`, `parallel_gate_check.py`, `hmte-final-check.sh`, `hmte-audit-flow.py`, `hmte-leader-jail.sh`, `hmte-goal-lock.sh`, `hmte-lint-protocol.sh`

**Risk Level**: P0 (Critical)

**Required Validations**:
- ✅ Syntax check (`bash -n` / `python3 -m py_compile`)
- ✅ **至少一个负向测试 case**
- ✅ E2E test coverage update
- ✅ Protocol lint pass
- ✅ All existing E2E tests pass (91/91)

**Negative Cases Required**:
- Missing evidence → gate FAIL
- Missing verdict → gate FAIL
- Invalid JSON → gate FAIL
- Protocol violation → gate FAIL

**Evidence Required**:
- Test output showing negative case blocked
- E2E test suite pass report

**Reviewer Focus**:
- Does gate actually block invalid input?
- Can the gate be bypassed?
- Are error messages clear?

---

### 2. Agent Prompt / Role Boundary

**Files**: `src/agents/*.md`

**Risk Level**: P1 (High)

**Required Validations**:
- ✅ Red-team adversarial test
- ✅ Role boundary test (Leader not doing Worker's job)
- ✅ E2E lifecycle test
- ✅ Human review of prompt clarity

**Negative Cases Required**:
- Leader trying to bypass delegation → blocked by Leader Jail
- Verifier trying to modify code → caught in review

**Evidence Required**:
- Red-team test results
- E2E test pass

**Reviewer Focus**:
- Are role boundaries clear?
- Can Agent bypass responsibilities?

---

### 3. Documentation Changes

**Files**: `README.md`, `HERMES.md`, `docs/*.md`

**Risk Level**: P2 (Medium)

**Required Validations**:
- ✅ Markdown syntax check
- ✅ Internal link validation
- ✅ Consistency with protocol
- ✅ Human review

**Negative Cases Required**:
- None (documentation is descriptive)

**Evidence Required**:
- Human review confirmation
- No broken links

**Reviewer Focus**:
- Is positioning consistent?
- Are examples up-to-date?
- Is terminology consistent (e.g., Final Verifier not Release Auditor)?

---

### 4. Schema Changes

**Files**: `evidence-schema.json`, `verdict-schema.json`, `PHASES_SCHEMA.md`

**Risk Level**: P1 (High)

**Required Validations**:
- ✅ JSON syntax check (for .json files)
- ✅ Backward compatibility test (old examples still valid)
- ✅ E2E test with new fields
- ✅ Protocol lint update
- ✅ **至少一个负向测试：invalid format → rejected**

**Negative Cases Required**:
- Invalid new field format → validation FAIL

**Evidence Required**:
- Schema validation test
- Backward compatibility test

**Reviewer Focus**:
- Are new fields optional?
- Do existing fixtures still pass?
- Is migration path clear?

---

### 5. Public-Safe Cleanup

**Files**: `scripts/pack-all-to-md.sh`, `.gitignore`

**Risk Level**: P0 (Critical)

**Required Validations**:
- ✅ **Grep check for sensitive content**
- ✅ No test_results.log in pack
- ✅ No local paths (`/Users/`) in pack
- ✅ No internal reports in pack
- ✅ .gitignore alignment with pack script

**Negative Cases Required**:
- pack-all-to-md.sh accidentally including excluded files → blocked by exclusion rules

**Evidence Required**:
- Grep verification pass:
  ```bash
  grep "/Users/" AUDIT_PACK.md
  grep "reviewer" AUDIT_PACK.md
  grep "test_results.log" AUDIT_PACK.md
  # All should have no output
  ```

**Reviewer Focus**:
- Can sensitive content leak?
- Is .gitignore aligned with pack script?
- Are exclusion rules tested?

---

### 6. Installer Changes

**Files**: `install-to-hermes.sh`

**Risk Level**: P1 (High)

**Required Validations**:
- ✅ Syntax check
- ✅ Fresh install test
- ✅ Upgrade test
- ✅ File path validation

**Negative Cases Required**:
- Install to invalid path → error with clear message

**Evidence Required**:
- Fresh install test log
- Upgrade test log

**Reviewer Focus**:
- Does install handle edge cases?
- Are error messages clear?

---

## Gate Test Policy

**门禁变更必须有负向测试**

任何修改以下文件，必须新增或更新至少一个负向测试 case：

- `phase_gate.sh`
- `parallel_gate_check.py`
- `hmte-final-check.sh`
- `hmte-audit-flow.py`
- `hmte-leader-jail.sh`
- `hmte-goal-lock.sh`
- `hmte-lint-protocol.sh`
- Evidence / Verdict / Receipt schema
- Agent role boundary prompts
- Installer critical files

**为什么**:
- 门禁是最后防线，必须确保真的生效
- 负向测试验证"坏输入被阻断"
- 防止门禁被意外绕过

**示例**:
```bash
# 新增 evidence field validation
# → 必须有测试：missing field → audit-flow FAIL

# 加强 parallel gate check
# → 必须有测试：forbidden_paths violation → gate FAIL
```

**不要求负向测试的情况**:
- 文档更新
- 非关键脚本
- 示例更新
- README 更新

---

## Validation Types

TriAgentFlow / TAF 认可多种验证方式：

1. **Automated Testing**
   - Unit tests
   - Integration tests
   - E2E tests
   - Negative tests

2. **Static Analysis**
   - Syntax check
   - Lint
   - Type check
   - Schema validation

3. **Build Verification**
   - Compile check
   - Dependency check
   - Install test

4. **Human Review**
   - Code review
   - Design review
   - Documentation review
   - Security review

5. **Grep / Pattern Check**
   - Public-safe scan
   - Terminology consistency check
   - Deprecated pattern detection

6. **Protocol Validation**
   - hmte-lint-protocol.sh
   - hmte-validate-phases.sh
   - Evidence / verdict schema check

---

## Enforcement

- Human review in PR
- CI should run relevant tests
- Reviewer checks: "Does this PR include required validations?"
- Not automated — relies on CONTRIBUTING.md guidance and PR review

---

## References

- [CONTRIBUTING.md](../CONTRIBUTING.md) — PR guidelines
- [COMPLEXITY_BUDGET.md](COMPLEXITY_BUDGET.md) — File/script budget
- [PROJECT_BOUNDARIES.md](PROJECT_BOUNDARIES.md) — Five constraints

---

**Document Version**: 1.8.0  
**Last Updated**: 2026-06-03  
**Status**: Authoritative
