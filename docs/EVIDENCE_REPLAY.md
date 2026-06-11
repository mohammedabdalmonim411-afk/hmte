# Evidence Replay

**Version**: 2.0  
**Compatible with**: TriAgentFlow / TAF v2.0+  
**Status**: Active  
**Scope**: MVP (dry-run / read-only / hash comparison only)  

---

## Overview

Evidence Replay 允许重放 evidence bundle 中记录的操作，验证一致性和可重现性。v2.0 MVP 仅支持 **dry-run**、**read-only** 和 **hash comparison** 模式，不支持 mutating command 执行。

---

## Modes

### 1. Dry-Run Mode (Default)

解析 evidence 和 command log，但不执行任何命令。

**用途**：
- 验证 evidence 结构完整性
- 检查 command log 格式
- 检查 plan_ref 引用

**示例**：
```bash
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode dry-run
```

**输出**：
- Evidence 结构验证结果
- Command log 解析结果
- Plan coverage 检查结果

### 2. Read-Only Mode

执行只读命令（read_file, search_files, terminal with read-only commands），不执行 mutating commands。

**用途**：
- 验证文件存在性
- 检查文件内容（不修改）
- 验证命令可重现性（只读部分）

**示例**：
```bash
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode read-only
```

**允许的命令**：
- `read_file`
- `search_files`
- `terminal` with read-only commands (grep, cat, ls, find)

**禁止的命令**：
- `write_file`
- `patch`
- `terminal` with mutating commands (rm, mv, sed -i)

### 3. Hash Comparison Mode

对比 evidence 中记录的文件 hash 与当前文件 hash，验证文件一致性。

**用途**：
- 验证文件未被修改
- 检测 evidence 与实际文件的差异
- 审计 evidence 完整性

**示例**：
```bash
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode hash-comparison
```

**输出**：
- 文件 hash 对比结果
- 不一致的文件列表
- Hash mismatch 详情

---

## Non-Scope: Mutating Replay

**v2.0 不支持 mutating replay**（带 `--exec` 的执行模式）。

**原因**：
- 安全风险高
- 需要 sandbox / allowlist / 用户确认
- 超出 v2.0 MVP 范围

**如需验证 mutating command 效果**：
- 重新执行对应 phase 的 Worker 任务
- 在 isolated environment 中手动重放

**Future (v2.1+)**：
- Sandbox execution
- Allowlist for mutating commands
- User confirmation required
- Replay audit log

---

## Evidence Replay Schema

### Input: Evidence Bundle

```json
{
  "phase_id": "phase_1",
  "attempt": 1,
  "plan_ref": {
    "plan_path": "HTE_v2.0_PROJECT_PLAN.md",
    "plan_hash": "sha256:abc123...",
    "plan_item_ids": ["S-001", "AC-001"]
  },
  "changed_files": ["docs/PLAN_CONTRACT.md"],
  "command_logs": [".phase_control/logs/phase_1_attempt_1.commands.jsonl"],
  "tests_run": ["T-001"],
  "file_hashes": {
    "docs/PLAN_CONTRACT.md": "sha256:def456..."
  }
}
```

### Output: Replay Report

```json
{
  "replay_mode": "hash-comparison",
  "evidence_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "status": "PASS",
  "checks_performed": [
    "evidence_structure",
    "command_log_parsing",
    "plan_coverage",
    "file_hash_comparison"
  ],
  "findings": [],
  "file_hash_comparison": {
    "total_files": 1,
    "matched": 1,
    "mismatched": 0,
    "missing": 0
  }
}
```

---

## Plan-Grounded Replay

Evidence Replay 必须验证 plan coverage：

### Plan Coverage Checks

1. **Evidence 引用 plan_ref**
   - evidence.plan_ref 存在
   - plan_ref.plan_hash 与 plan_lock 一致
   - plan_ref.plan_item_ids 非空

2. **Command log 完整性**
   - command_logs 路径存在
   - command log 格式有效
   - command log 可解析

3. **Changed files 验证**
   - changed_files 路径存在（read-only mode）
   - file_hashes 匹配（hash-comparison mode）

---

## Usage Examples

### Example 1: Dry-Run Verification

```bash
# 验证 evidence 结构完整性
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode dry-run

# 输出
Evidence structure: VALID
Command log parsing: SUCCESS
Plan coverage: PASS
  - plan_ref present
  - plan_hash matches lock
  - plan_item_ids: S-001, AC-001
```

### Example 2: Hash Comparison

```bash
# 验证文件 hash 一致性
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode hash-comparison

# 输出
File hash comparison: PASS
  - docs/PLAN_CONTRACT.md: MATCH
  - scripts/hmte-plan-contract.sh: MATCH
Total: 2 files, 2 matched, 0 mismatched
```

### Example 3: Read-Only Replay

```bash
# 验证文件存在性和内容（只读）
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode read-only

# 输出
Read-only replay: SUCCESS
  - docs/PLAN_CONTRACT.md: EXISTS
  - Command: read_file docs/PLAN_CONTRACT.md: SUCCESS
  - Command: grep "Plan Contract" docs/PLAN_CONTRACT.md: SUCCESS
```

---

## Error Scenarios

### Corrupted Evidence

```bash
# Evidence JSON 格式错误
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/corrupted.json \
  --mode dry-run

# 输出
ERROR: Evidence JSON parse failed
  File: .phase_control/evidence/corrupted.json
  Error: Unexpected token } in JSON at position 123
  Status: FAIL
```

### Missing Command Log

```bash
# Command log 文件不存在
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode read-only

# 输出
ERROR: Command log not found
  Expected: .phase_control/logs/phase_1_attempt_1.commands.jsonl
  Status: FAIL
```

### Hash Mismatch

```bash
# 文件 hash 不匹配
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode hash-comparison

# 输出
ERROR: File hash mismatch
  File: docs/PLAN_CONTRACT.md
  Expected: sha256:def456...
  Actual: sha256:xyz789...
  Status: FAIL
```

---

## Verification

### Required Checks

- [ ] Evidence structure valid
- [ ] Command log parseable
- [ ] Plan coverage verified
- [ ] File hashes match (hash-comparison mode)
- [ ] Read-only commands succeed (read-only mode)
- [ ] No mutating commands executed

### Negative Tests

- Corrupted evidence → FAIL
- Missing command log → FAIL
- Missing files → FAIL
- Hash mismatch → FAIL
- Mutating command in read-only mode → FAIL

---

## Integration with phase_gate

phase_gate 可以使用 Evidence Replay 验证 evidence 完整性：

```bash
# phase_gate 调用 evidence replay
bash scripts/phase_gate.sh \
  --phase-id phase_1 \
  --check-evidence-replay

# 内部调用
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode dry-run
```

---

## Future Enhancements (v2.1+)

### Mutating Replay (Sandbox)

```bash
# NOT supported in v2.0
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --mode exec \
  --sandbox docker \
  --allowlist "write_file,patch" \
  --confirm

# 需要实现：
# - Docker/VM sandbox
# - Allowlist for mutating commands
# - User confirmation prompt
# - Replay audit log
```

### Replay Diff

```bash
# NOT supported in v2.0
bash scripts/hmte-evidence-replay.sh \
  --evidence .phase_control/evidence/phase_1_attempt_1.json \
  --evidence-compare .phase_control/evidence/phase_1_attempt_2.json \
  --mode diff
```

---

## Success Criteria

- [ ] Dry-run mode 验证 evidence 结构
- [ ] Read-only mode 执行只读命令
- [ ] Hash comparison mode 验证文件一致性
- [ ] Plan coverage 验证通过
- [ ] Mutating command 不在 v2.0 范围内
- [ ] 负向测试覆盖

---

**Last Updated**: 2026-06-10  
**Maintainer**: TAF Core Team
