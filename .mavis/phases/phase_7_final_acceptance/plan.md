# Phase 7: 最终验收 (phase_7_final_acceptance)

## 目标
运行完整测试套件，验证 v1.4 所有交付物的功能和文档一致性，执行 Release Auditor final_audit。

## 验收命令清单（17 个命令）

### 1. 基础检查（3 个命令）
```bash
bash -n scripts/hmte-lint-protocol.sh
bash -n scripts/test-protocol-lint.sh
bash -n scripts/hmte-claims.sh
```

### 2. 协议检查（2 个命令）
```bash
bash scripts/hmte-lint-protocol.sh
bash scripts/test-protocol-lint.sh
```

### 3. 能力声明（1 个命令）
```bash
bash scripts/hmte-claims.sh
```

### 4. 生命周期测试（3 个命令）
```bash
bash scripts/e2e-lifecycle-test.sh
bash scripts/e2e-core-workflow-test.sh
bash scripts/e2e-anti-fake-test.sh
```

### 5. Phase 2 验收（1 个命令）
```bash
bash scripts/test-phase2-acceptance.sh
```

### 6. 文档检查（7 个命令）
```bash
grep -q "v1.4.0" README.md && echo "✅ README.md 版本号正确"
grep -q "文件协议工作流框架" README.md && echo "✅ README.md 定位正确"
grep -q "\[1.4.0\]" CHANGELOG.md && echo "✅ CHANGELOG.md 版本记录存在"
grep -q "hmte-lint-protocol" HERMES.md && echo "✅ HERMES.md 包含协议检查说明"
grep -q "hmte-claims" HERMES.md && echo "✅ HERMES.md 包含能力声明说明"
grep -q "team-rules" HERMES.md && echo "✅ HERMES.md 包含团队规则说明"
grep -q "文件协议工作流框架" src/skills/hmte/SKILL.md && echo "✅ SKILL.md 定位正确"
```

## 验收标准
1. 所有 17 个命令执行成功（exit code 0）
2. 协议检查脚本无错误输出
3. 测试套件全部通过
4. 文档检查全部通过
5. 证据链完整（Phase 1-6 的 evidence + verdicts + receipts）

## 产出
- `worker.evidence.json`: 包含所有 17 个命令的执行结果
- `worker.command_log.txt`: 完整的命令执行日志

## 后续步骤
Worker 完成后，委派 Release Auditor 执行 final_audit，审计所有 Phase 1-7 的证据链和文档一致性。
