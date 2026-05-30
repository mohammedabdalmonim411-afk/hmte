# Phase 5: docs/attack-cases.md

## Objective
Create attack cases documentation that honestly explains common attack/forgery paths and HTE's current detection capabilities.

## Scope
- Create `docs/attack-cases.md`
- Document common attack vectors
- Clarify what HTE can detect vs. what it cannot
- Be honest about limitations

## Success Criteria
- File created with comprehensive attack case coverage
- Covers all 7 required attack vectors
- Honest about detection capabilities and limitations
- File is excluded from hmte-lint-protocol.sh scanning

## Required Attack Vectors
1. 手写 PASS verdict (manually written PASS verdict)
2. 不走 hmte exec (bypassing hmte exec)
3. receipt 声称 OBSERVED 但无 trace (claiming OBSERVED without trace)
4. evidence 手写但无 command log (manual evidence without command log)
5. 同一 AI 自演多角色 (same AI playing multiple roles)
6. 文档脚本口径漂移 (documentation/script inconsistency drift)
7. E2E 构造文件但不代表真实 Agent 运行 (E2E constructs files but doesn't represent real Agent execution)

## Constraints
- Be honest about what HTE can and cannot detect
- Explain current detection mechanisms
- Clarify limitations without over-promising
- This file will be excluded from protocol lint scanning
