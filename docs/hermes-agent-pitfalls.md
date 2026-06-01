# Hermes Agent 工具使用坑点总结

> **目的**：记录 Hermes Agent 工具调用中遇到的坑点和最佳实践，避免未来重复犯错。

---

## 1. write_file 工具 - 大文件内容丢失

### 问题描述
- **症状**：调用 `write_file` 时只传了 `path`，`content` 参数丢失
- **错误信息**：`missing required field 'content'`
- **触发条件**：内容超过 10KB，在上下文压力下参数被截断

### 根本原因
- 工具调用时，大型 `content` 参数在序列化过程中被截断
- 上下文压力导致参数丢失

### 解决方案
**优先级排序**：
1. **terminal + cat + heredoc**（最可靠）
   ```bash
   cat > /path/to/file << 'EOF'
   [大量内容]
   EOF
   ```
2. **execute_code + hermes_tools.write_file() + 绝对路径**
   ```python
   from hermes_tools import write_file
   content = """[大量内容]"""
   write_file('/absolute/path/to/file', content)
   ```
3. **write_file 工具**（仅适用于小文件 < 5KB）

### 最佳实践
- 内容 > 10KB：使用 terminal + cat
- 内容 5-10KB：使用 execute_code + hermes_tools
- 内容 < 5KB：可以使用 write_file 工具

---

## 2. hermes_tools.write_file() - 相对路径不可靠

### 问题描述
- **症状**：`execute_code` 返回成功，但文件实际未写入预期位置
- **触发条件**：使用相对路径（如 `docs/file.md`）

### 根本原因
- `hermes_tools.write_file()` 的相对路径解析可能基于不同的工作目录
- 返回成功消息但文件写入到了错误位置

### 解决方案
1. **使用绝对路径**
   ```python
   write_file('/Users/zhouchang/ai/project/docs/file.md', content)
   ```
2. **或先构造绝对路径**
   ```python
   import os
   base = '/Users/zhouchang/ai/project'
   path = os.path.join(base, 'docs', 'file.md')
   write_file(path, content)
   ```

### 最佳实践
- 优先使用绝对路径
- 如果必须用相对路径，先用 `terminal` 验证工作目录

---

## 3. execute_code - 空参数调用

### 问题描述
- **症状**：调用 `execute_code` 但 `code` 参数为空
- **错误信息**：`No code provided`
- **触发条件**：工具调用策略切换时构造出错

### 根本原因
- 在切换工具策略时，新的工具调用构造不完整
- 参数准备不充分就发起调用

### 解决方案
- 切换策略前，先完整准备好新工具的所有参数
- 不要在失败后立即重试相同策略

### 最佳实践
- 工具调用失败 2 次后，必须切换策略
- 切换前明确新策略的完整参数

---

## 4. 工具调用失败循环

### 问题描述
- **症状**：连续多次相同工具调用失败
- **系统警告**：`repeated_exact_failure_warning`

### 根本原因
- 未分析失败原因就重复相同调用
- 期望"再试一次就能成功"

### 解决方案
**失败处理流程**：
1. **第 1 次失败**：分析错误信息，调整参数重试
2. **第 2 次失败**：切换工具或策略
3. **第 3 次失败**：向用户说明问题，请求指导

### 最佳实践
- 不要重复相同的失败调用超过 2 次
- 每次失败后必须改变策略

---

## 5. 大文件写入 - 策略选择矩阵

| 文件大小 | 内容类型 | 推荐工具 | 备选方案 |
|---------|---------|---------|---------|
| < 5KB | 任意 | write_file | terminal + cat |
| 5-10KB | 结构化 | execute_code + hermes_tools | terminal + cat |
| 10-50KB | 任意 | terminal + cat + heredoc | execute_code（分块） |
| > 50KB | 任意 | terminal + cat + heredoc | 不推荐一次性写入 |

---

## 6. 路径解析 - 安全实践

### 问题场景
- 相对路径在不同工具中解析不一致
- 跨 profile 操作时路径混淆

### 最佳实践
1. **优先使用绝对路径**
2. **相对路径前先验证工作目录**
   ```bash
   pwd
   ls -la target/path
   ```
3. **跨 profile 操作必须使用绝对路径**

---

## 7. 工具选择 - 决策树

```
需要写文件？
├─ 内容 < 5KB？
│  └─ 是 → write_file
└─ 否
   ├─ 内容 < 50KB？
   │  └─ 是 → terminal + cat + heredoc
   └─ 否 → 分块写入或生成后再写

需要读文件？
├─ 文件 < 100KB？
│  └─ 是 → read_file
└─ 否 → read_file + offset/limit 分页

需要执行多步骤逻辑？
├─ 步骤 < 3？
│  └─ 是 → 直接工具调用
└─ 否 → execute_code

需要委派子任务？
├─ 需要推理？
│  └─ 是 → delegate_task
└─ 否 → execute_code
```

---

## 8. 经验教训

1. **大文件写入**：超过 10KB 优先用 terminal + cat
2. **相对路径**：hermes_tools 相对路径不可靠，优先绝对路径
3. **失败重试**：不要重复相同失败超过 2 次
4. **策略切换**：失败后立即切换，不要期望"再试一次"
5. **参数完整性**：切换工具前确保新工具参数完整
6. **验证结果**：工具返回成功后，用独立方式验证（如 ls / read_file）

---

## 9. 未来改进建议

1. **write_file 工具**：增加内容大小限制提示
2. **hermes_tools**：统一相对路径解析规则
3. **工具调用**：增加参数完整性检查
4. **错误处理**：提供更明确的失败原因和建议策略

---

**最后更新**：2026-05-31  
**维护者**：Kiro (Claude Opus 4)
