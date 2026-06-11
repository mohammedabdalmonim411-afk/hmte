#!/usr/bin/env bash
# pack-all-to-md.sh
# 将项目文件打包为单一 Markdown 文件，用于 AI 审计
# v2.0: 强制 UTF-8，动态摘要，防套娃，防旧口径泄露
#
# 用法:
#   pack-all-to-md.sh --markdown --profile ai-core    TriAgentFlow_v2.0_ai-core_AUDIT_PACK.md
#   pack-all-to-md.sh --markdown --profile ai-dogfood TriAgentFlow_v2.0_ai-dogfood_AUDIT_PACK.md
#   pack-all-to-md.sh --markdown --profile ai-full    TriAgentFlow_v2.0_ai-full_AUDIT_PACK.md
#   pack-all-to-md.sh --markdown --profile ai-all     TriAgentFlow_v2.0_ai-all_AUDIT_PACK.md

set -euo pipefail

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MODE="md"
OUTPUT_FILE=""
PROFILE="ai-core"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --markdown) MODE="md"; shift ;;
        --profile) shift; PROFILE="$1"; shift ;;
        *) OUTPUT_FILE="$1"; shift ;;
    esac
done

case "$PROFILE" in
    ai-core|ai-dogfood|ai-full|ai-all) ;;
    *)
        echo "Unknown profile: $PROFILE (valid: ai-core, ai-dogfood, ai-full, ai-all)" >&2
        exit 1
        ;;
esac

OUTPUT_FILE="${OUTPUT_FILE:-${PROJECT_ROOT}/TAF_v2.0_${PROFILE}_AUDIT_PACK.md}"
if [[ "$OUTPUT_FILE" != /* ]]; then
    OUTPUT_FILE="${PROJECT_ROOT}/${OUTPUT_FILE}"
fi
PACK_OUTPUT_REL="${OUTPUT_FILE#$PROJECT_ROOT/}"
PACK_OUTPUT_BASENAME="$(basename "$OUTPUT_FILE")"

echo "Pack mode: Markdown, profile: $PROFILE"
echo "Project root: $PROJECT_ROOT"
echo "Output file: $OUTPUT_FILE"
echo ""

# ============================================================
#  动态验证 — 运行命令获取真实结果，禁止硬编码
# ============================================================
cd "$PROJECT_ROOT"

strip_ansi() {
    perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'
}

display_file_label() {
    case "$1" in
        HTE_v2.0_PROJECT_PLAN.md)
            printf '%s' "TAF_v2.0_PROJECT_PLAN.md (source path retained for legacy compatibility)"
            ;;
        HTE_v1.9_PROJECT_PLAN.md)
            printf '%s' "Legacy_v1.9_PROJECT_PLAN.md (historical archive)"
            ;;
        HTE_v1.9_to_v2.0_MASTER_ROADMAP.md)
            printf '%s' "Legacy_v1.9_to_v2.0_MASTER_ROADMAP.md (historical archive)"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

sanitize_pack_text() {
    sed \
        -e 's/HTE_v2\.0_PROJECT_PLAN\.md/TAF_v2.0_PROJECT_PLAN.md (legacy source path)/g' \
        -e 's/HTE_v1\.9_PROJECT_PLAN\.md/Legacy_v1.9_PROJECT_PLAN.md/g' \
        -e 's/HTE_v1\.9_to_v2\.0_MASTER_ROADMAP\.md/Legacy_v1.9_to_v2.0_MASTER_ROADMAP.md/g' \
        -e 's/HTE_v[0-9.]*_COMPLETION_REPORT\.md/LegacyCompletionReport.md/g' \
        -e 's/PHASE_[0-9][0-9]*_[A-Z0-9_]*\.md/LegacyPhaseReport.md/g'
}

pack_file_text() {
    local filepath="$1"
    if [[ "$PROFILE" == "ai-full" || "$PROFILE" == "ai-all" ]]; then
        cat "$filepath"
    else
        cat "$filepath" | sanitize_pack_text
    fi
}

add_pack_file() {
    local candidate="$1"
    if [[ ! " ${PACK_FILES[*]:-} " =~ " ${candidate} " ]]; then
        PACK_FILES+=("$candidate")
    fi
}

record_skipped_file() {
    local file="$1"
    local reason="$2"
    printf '%s\t%s\n' "$file" "$reason" >> "$SKIP_MANIFEST_TEMP"
}

full_pack_skip_reason() {
    local file="$1"

    if [[ "$file" == "$PACK_OUTPUT_REL" || "$(basename "$file")" == "$PACK_OUTPUT_BASENAME" ]]; then
        printf '%s' "current output file / self-nesting prevention"
        return 0
    fi

    case "$file" in
        .git/*)
            printf '%s' "git metadata"
            ;;
        .phase_control/*|.phase_control_archive/*)
            printf '%s' "runtime/private session state"
            ;;
        dogfood_regression/*|private_validation/*|dev/*)
            printf '%s' "local/private generated validation artifact"
            ;;
        node_modules/*|.venv/*|venv/*|__pycache__/*|*/__pycache__/*)
            printf '%s' "dependency/cache artifact"
            ;;
        .DS_Store|*/.DS_Store)
            printf '%s' "OS metadata"
            ;;
        *.log|test_results.log)
            printf '%s' "log output"
            ;;
        *.tar.gz|*.tgz|*.zip|*.gz|*.bz2|*.xz)
            printf '%s' "archive/compressed artifact"
            ;;
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.mov|*.mp4|*.mp3|*.wav)
            printf '%s' "binary/media artifact"
            ;;
        hmte-full-pack-*.md|hmte-pack-*|*_AUDIT_PACK.md|*_FULL_PACK.md|HTE_v2.0_EXTERNAL_AUDIT_PACK.md|TAF_v2.0_ai-*_AUDIT_PACK.md|TriAgentFlow_v2.0_ai-*_AUDIT_PACK.md)
            printf '%s' "generated audit pack / self-nesting prevention"
            ;;
        *)
            return 1
            ;;
    esac
}

EVAL_OUTPUT=""
EVAL_PASSED=false
EVAL_TEMP="$(mktemp)"
LAZY_TEMP="$(mktemp)"
SKIP_MANIFEST_TEMP="$(mktemp)"
cleanup_pack_temps() {
    rm -f "$EVAL_TEMP" "$LAZY_TEMP" "$SKIP_MANIFEST_TEMP"
}
trap cleanup_pack_temps EXIT

if bash scripts/hmte-eval.sh > "$EVAL_TEMP" 2>&1; then
    EVAL_PASSED=true
fi
EVAL_OUTPUT=$(tail -8 "$EVAL_TEMP" 2>/dev/null || echo "[eval not run]")
EVAL_SUMMARY=$(grep -E 'Results: [0-9]+ passed, [0-9]+ failed' "$EVAL_TEMP" 2>/dev/null || echo "Results: [eval not run]")

RG_OUTPUT=$(bash scripts/hmte-release-gate.sh --mode audit 2>&1) && RG_EXIT=0 || RG_EXIT=$?
RG_CLEAN=$(printf '%s\n' "$RG_OUTPUT" | strip_ansi)
RG_P0=$(echo "$RG_CLEAN" | grep -Eo 'P0 issues: [0-9]+' || echo "P0 issues: ?")
RG_P1=$(echo "$RG_CLEAN" | grep -Eo 'P1 issues: [0-9]+' || echo "P1 issues: ?")
RG_P2=$(echo "$RG_CLEAN" | grep -Eo 'P2 issues: [0-9]+' || echo "P2 issues: ?")
RG_CHECKS=$(echo "$RG_CLEAN" | grep -Eo 'Checks: [0-9]+/[0-9]+ passed' || echo "Checks: ?/?")
RG_VERDICT=$(echo "$RG_CLEAN" | grep -Eo 'VERDICT: .+' | head -1 || echo "VERDICT: ?")
RG_SUMMARY=$(printf '%s\n' "$RG_CLEAN" | tail -18)

STRICT_RG_OUTPUT=$(bash scripts/hmte-release-gate.sh --mode release 2>&1) && STRICT_RG_EXIT=0 || STRICT_RG_EXIT=$?
STRICT_RG_CLEAN=$(printf '%s\n' "$STRICT_RG_OUTPUT" | strip_ansi)
STRICT_RG_P0=$(echo "$STRICT_RG_CLEAN" | grep -Eo 'P0 issues: [0-9]+' || echo "P0 issues: ?")
STRICT_RG_P1=$(echo "$STRICT_RG_CLEAN" | grep -Eo 'P1 issues: [0-9]+' || echo "P1 issues: ?")
STRICT_RG_P2=$(echo "$STRICT_RG_CLEAN" | grep -Eo 'P2 issues: [0-9]+' || echo "P2 issues: ?")
STRICT_RG_CHECKS=$(echo "$STRICT_RG_CLEAN" | grep -Eo 'Checks: [0-9]+/[0-9]+ passed' || echo "Checks: ?/?")
STRICT_RG_VERDICT=$(echo "$STRICT_RG_CLEAN" | grep -Eo 'VERDICT: .+' | head -1 || echo "VERDICT: ?")
STRICT_RG_SUMMARY=$(printf '%s\n' "$STRICT_RG_CLEAN" | tail -18)

FC_OUTPUT=$(bash scripts/hmte-final-check.sh --mode release 2>&1) && FC_EXIT=0 || FC_EXIT=$?
FC_CLEAN=$(printf '%s\n' "$FC_OUTPUT" | strip_ansi)
FC_SUMMARY=$(printf '%s\n' "$FC_CLEAN" | tail -18)
FC_RESULT="FINAL-CHECK-NOT-PASSED"
if [ "$FC_EXIT" -eq 0 ]; then
    FC_RESULT="FINAL-CHECK-PASSED"
fi

LAZY_OUTPUT=""
LAZY_PASS=0
LAZY_FAIL=0
for lazy_test in evals/fixtures/lazy-path-*/test.sh; do
    [ -f "$lazy_test" ] || continue
    : > "$LAZY_TEMP"
    if bash "$lazy_test" > "$LAZY_TEMP" 2>&1; then
        LAZY_PASS=$((LAZY_PASS + 1))
        LAZY_OUTPUT="${LAZY_OUTPUT}PASS $(basename "$(dirname "$lazy_test")")"$'\n'
    else
        LAZY_FAIL=$((LAZY_FAIL + 1))
        LAZY_OUTPUT="${LAZY_OUTPUT}FAIL $(basename "$(dirname "$lazy_test")")"$'\n'
        LAZY_OUTPUT="${LAZY_OUTPUT}$(tail -12 "$LAZY_TEMP")"$'\n'
    fi
done
LAZY_SUMMARY="Lazy-path: ${LAZY_PASS}/11 PASS, ${LAZY_FAIL} FAIL"

# ============================================================
#  外部审计 receipt 状态 — 动态计算 Known Open Issues
#  口径必须与 EXTERNAL_AUDIT_RECEIPT.md 及 strict release gate 一致，
#  禁止硬编码旧的 "Not bundled" / "remains blocked" 文案。
# ============================================================
RECEIPT_PATH=""
if [ -f ".phase_control/external_audit_receipt.json" ]; then
    RECEIPT_PATH=".phase_control/external_audit_receipt.json"
elif [ -f "EXTERNAL_AUDIT_RECEIPT.md" ]; then
    RECEIPT_PATH="EXTERNAL_AUDIT_RECEIPT.md"
fi

# 从 receipt 读取 Open P0/P1/P2（取冒号后的数值，避免误取标签里的 P1/P2 数字）
RECEIPT_P0="?"; RECEIPT_P1="?"; RECEIPT_P2="?"
if [ -n "$RECEIPT_PATH" ] && [ -f "$RECEIPT_PATH" ]; then
    RECEIPT_P0=$(grep -Ei 'Open[[:space:]]+P0[[:space:]]*:' "$RECEIPT_PATH" | head -1 | sed -E 's/.*Open[[:space:]]+P0[[:space:]]*:[[:space:]]*([0-9]+).*/\1/I' || true)
    RECEIPT_P1=$(grep -Ei 'Open[[:space:]]+P1[[:space:]]*:' "$RECEIPT_PATH" | head -1 | sed -E 's/.*Open[[:space:]]+P1[[:space:]]*:[[:space:]]*([0-9]+).*/\1/I' || true)
    RECEIPT_P2=$(grep -Ei 'Open[[:space:]]+P2[[:space:]]*:' "$RECEIPT_PATH" | head -1 | sed -E 's/.*Open[[:space:]]+P2[[:space:]]*:[[:space:]]*([0-9]+).*/\1/I' || true)
    [[ "$RECEIPT_P0" =~ ^[0-9]+$ ]] || RECEIPT_P0="?"
    [[ "$RECEIPT_P1" =~ ^[0-9]+$ ]] || RECEIPT_P1="?"
    [[ "$RECEIPT_P2" =~ ^[0-9]+$ ]] || RECEIPT_P2="?"
fi

# strict release gate 通过 (exit 0) 时，receipt 已绑定且 release/publishing 不再被阻断
if [ "${STRICT_RG_EXIT}" -eq 0 ] && [ -n "$RECEIPT_PATH" ]; then
    KNOWN_P1_STRICT="0"
    RECEIPT_STATUS_LINE="Bundled in audit pack and present in working tree (\`${RECEIPT_PATH}\`)"
    PUBLISH_BOUNDARY_LINE="Strict release gate passed (exit 0). Release artifacts must match the receipt before publishing."
else
    KNOWN_P1_STRICT="1"
    RECEIPT_STATUS_LINE="Not present or not release-valid; strict release gate does not pass."
    PUBLISH_BOUNDARY_LINE="Strict release gate did not pass; release/GitHub publishing remains blocked until a valid receipt is on file."
fi

# Known Open Issues 计数口径以 receipt 为准（外部审计结论），回退到 gate 计数
KNOWN_P0="${RECEIPT_P0}"
KNOWN_P1_READINESS="${RECEIPT_P1}"
KNOWN_P2="${RECEIPT_P2}"
if [ "$KNOWN_P0" = "?" ]; then KNOWN_P0="${STRICT_RG_P0//P0 issues: /}"; fi
if [ "$KNOWN_P1_READINESS" = "?" ]; then KNOWN_P1_READINESS="${STRICT_RG_P1//P1 issues: /}"; fi
if [ "$KNOWN_P2" = "?" ]; then KNOWN_P2="${STRICT_RG_P2//P2 issues: /}"; fi

# ============================================================
#  文件列表定义
# ============================================================

declare -a AI_CORE_FILES=(
    ".gitignore"
    "README.md"
    "HERMES.md"
    "HTE_v2.0_PROJECT_PLAN.md"
    "VALIDATION_SUMMARY_v2.0.md"
    "docs/HTE_PROTOCOL.md"
    "docs/PROJECT_BOUNDARIES.md"
    "docs/COMPLEXITY_BUDGET.md"
    "docs/RELEASE_GATE_PROTOCOL.md"
    "docs/AUDIT_PACK_MODES.md"
    "docs/PLAN_CONTRACT.md"
    "docs/PLAN_LOCK.md"
    "docs/PLAN_TO_DELEGATION_FIDELITY.md"
    "docs/VERIFIER_MANDATE.md"
    "docs/PLAN_COVERAGE_GATE.md"
    "docs/ANOMALY_LEDGER.md"
    "docs/TEST_DISPOSITION_GATE.md"
    "docs/PASS_CONTRADICTION.md"
    "docs/ZERO_FINDING.md"
    "scripts/hmte-eval.sh"
    "scripts/hmte-release-gate.sh"
    "scripts/hmte-final-check.sh"
    "scripts/hmte-audit-pack.sh"
    "scripts/pack-all-to-md.sh"
    "scripts/hmte-plan-contract.sh"
    "scripts/hmte-plan-lock.sh"
    "scripts/hmte-check-fidelity.sh"
    "scripts/hmte-check-mandate.sh"
    "scripts/hmte-anomaly-ledger.sh"
    "scripts/hmte-test-disposition.sh"
    "scripts/hmte-pass-contradiction.sh"
    "src/skills/hmte/scripts/phase_gate.sh"
    "evidence-schema.json"
    "verdict-schema.json"
    "src/skills/hmte/evidence-schema.json"
    "src/skills/hmte/verdict-schema.json"
    "src/skills/hmte/delegation-receipt-schema.json"
)

declare -a AI_DOGFOOD_EXTRA=(
    "docs/dogfood/TAF_v2.0_FINAL_REAL_WORLD_DOGFOOD_REPORT.md"
)

PACK_SCOPE="Curated external audit subset"

if [[ "$PROFILE" == "ai-core" ]]; then
    PACK_FILES=("${AI_CORE_FILES[@]}")
elif [[ "$PROFILE" == "ai-dogfood" ]]; then
    PACK_FILES=("${AI_CORE_FILES[@]}" "${AI_DOGFOOD_EXTRA[@]}")
elif [[ "$PROFILE" == "ai-full" || "$PROFILE" == "ai-all" ]]; then
    PACK_FILES=()
    PACK_SCOPE="All auditable project text files, excluding git metadata, runtime/private state, generated packs, logs, archives, and binary/media files"
else
    echo "Unknown profile: $PROFILE (valid: ai-core, ai-dogfood, ai-full, ai-all)" >&2
    exit 1
fi

if [[ "$PROFILE" == "ai-full" || "$PROFILE" == "ai-all" ]]; then
    while IFS= read -r file; do
        if reason="$(full_pack_skip_reason "$file")"; then
            record_skipped_file "$file" "$reason"
        else
            add_pack_file "$file"
        fi
    done < <(find . -type f | sed 's#^./##' | sort)
fi

while IFS= read -r file; do
    add_pack_file "$file"
done < <(find evals/cases -name '*.sh' 2>/dev/null | sed 's#^./##' | sort)

while IFS= read -r file; do
    add_pack_file "$file"
done < <(find evals/fixtures -type f \( -path '*/lazy-path-*/*' -o -path '*/valid_sequential/*' \) 2>/dev/null | sed 's#^./##' | sort)

# ============================================================
#  Git 快照
# ============================================================
GIT_STATUS_SNAPSHOT="$(git status --short 2>/dev/null || echo 'Not a git repository')"
GIT_DIFF_STAT_SNAPSHOT="$(git diff --stat 2>/dev/null || echo 'No diff')"

# ============================================================
#  审计包 Header — 动态内容，禁止硬编码
# ============================================================
EVAL_STATUS="FAIL"
if $EVAL_PASSED; then EVAL_STATUS="PASS"; fi

cat > "$OUTPUT_FILE" <<HEADER
# TriAgentFlow / TAF v2.0 — ${PROFILE} Audit Pack

> **Project**: TriAgentFlow / TAF
> **Chinese**: 三角色智能体开发工作流
> **Formerly**: HTE / Hermes Team Engine
> **Generated**: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
> **Profile**: ${PROFILE}
> **Pack Scope**: ${PACK_SCOPE}
> **Encoding**: UTF-8
> **Purpose**: External AI audit

---

## Validation Summary

### Eval Harness

\`\`\`
${EVAL_OUTPUT}
\`\`\`

**Eval Result**: ${EVAL_SUMMARY} — ${EVAL_STATUS}

### Release Gate (Audit Mode)

\`\`\`
${RG_CHECKS}
${RG_P0}
${RG_P1}
${RG_P2}
${RG_VERDICT}
Exit code: ${RG_EXIT}
\`\`\`

Full summary:

\`\`\`
${RG_SUMMARY}
\`\`\`

**Release Gate**: ${RG_VERDICT//VERDICT: /}

### Strict Release Gate

\`\`\`
${STRICT_RG_CHECKS}
${STRICT_RG_P0}
${STRICT_RG_P1}
${STRICT_RG_P2}
${STRICT_RG_VERDICT}
Exit code: ${STRICT_RG_EXIT}
\`\`\`

Full summary:

\`\`\`
${STRICT_RG_SUMMARY}
\`\`\`

**Strict Release Gate**: ${STRICT_RG_VERDICT//VERDICT: /}

### Final Check

\`\`\`
Exit code: ${FC_EXIT}
${FC_SUMMARY}
\`\`\`

**Final Check**: ${FC_RESULT}

### Lazy-Path Dogfood

\`\`\`
${LAZY_SUMMARY}
${LAZY_OUTPUT}
\`\`\`

### Known Open Issues

**P0**: ${KNOWN_P0}
**P1 (external-audit readiness)**: ${KNOWN_P1_READINESS}
**P1 (strict release)**: ${KNOWN_P1_STRICT}
**P2**: ${KNOWN_P2}
**External Audit Receipt**: ${RECEIPT_STATUS_LINE}

> **Publishing boundary**: ${PUBLISH_BOUNDARY_LINE}
> **Trust level**: Dogfood validation uses INTENT_ONLY receipts, not OBSERVED delegate_task proof; this must not be overclaimed.

---

## Project Overview

TriAgentFlow / TAF v2.0 — 三角色智能体开发工作流 (Three-Agent Development Workflow).
Leader / Worker / Verifier three-role skeleton with plan-grounded audit chain.

hmte is a legacy internal command prefix retained for backward compatibility.

**v2.0 Core Mechanisms (9 P0)**:
- Plan Contract: Plan locking + amendment tracking
- Plan Lock: Plan hash + tamper detection
- Plan-to-Delegation Fidelity: Worker faithfully executes plan
- Verifier Mandate: Audit scope must cover changes
- Plan Coverage Gate: Complete plan item coverage verification
- Anomaly Ledger: Anomaly recording + disposition tracking
- Test Disposition Gate: Failed/skipped tests must have disposition
- PASS Contradiction: Detect declaration vs evidence conflicts
- Zero-Finding Justification: Zero findings require evidence anchor

**Constitutional Compliance (5/5)**:
- Three-Agent Core: Leader / Worker / Verifier
- Gate Authority: Plan Lock + Gate checks override declarations
- Evidence First: Evidence + Verdict must reference plan items
- Universal Design: Protocol-generic, not tool/language bound
- No Over-Engineering: No runtime, daemon, SQLite, dashboard, DAG

---
HEADER

# ============================================================
#  打包每个文件
# ============================================================
packed=0
skipped=0

cd "$PROJECT_ROOT"
for file in "${PACK_FILES[@]}"; do
    filepath="$PROJECT_ROOT/$file"

    if [ ! -f "$filepath" ]; then
        echo "  skip (not found): $file"
        skipped=$((skipped + 1))
        continue
    fi

    if ! LC_ALL=C grep -Iq "" "$filepath"; then
        echo "  skip (non-text): $file"
        record_skipped_file "$file" "non-text file detected at pack time"
        skipped=$((skipped + 1))
        continue
    fi

    echo "  pack: $file"
    packed=$((packed + 1))

    {
        printf '\n\n## File: `%s`\n\n' "$(display_file_label "$file")"
        printf '```text\n'
        pack_file_text "$filepath"
        printf '\n```\n'
    } >> "$OUTPUT_FILE"
done

SKIPPED_MANIFEST_COUNT="$(wc -l < "$SKIP_MANIFEST_TEMP" | tr -d ' ')"

if [ -s "$SKIP_MANIFEST_TEMP" ]; then
    cat >> "$OUTPUT_FILE" <<SKIPPED

---

## Skipped Files Manifest

These files were intentionally excluded from this audit pack. The full pack includes all auditable project text files and excludes only generated packs, git metadata, runtime/private state, logs, archives, caches, and binary/media files.

| File | Reason |
|------|--------|
SKIPPED
    while IFS=$'\t' read -r skipped_file skipped_reason; do
        printf '| `%s` | %s |\n' "$skipped_file" "$skipped_reason" >> "$OUTPUT_FILE"
    done < "$SKIP_MANIFEST_TEMP"
fi

# ============================================================
#  Git 信息附录
# ============================================================
cat >> "$OUTPUT_FILE" <<GITINFO

---

## git status --short

\`\`\`text
$(printf '%s\n' "$GIT_STATUS_SNAPSHOT" | sanitize_pack_text)
\`\`\`

---

## git diff --stat

\`\`\`text
$(printf '%s\n' "$GIT_DIFF_STAT_SNAPSHOT" | sanitize_pack_text)
\`\`\`

---

## Pack Metadata

| Field | Value |
|-------|-------|
| Profile | ${PROFILE} |
| Generated | $(date -u '+%Y-%m-%dT%H:%M:%SZ') |
| Files packed | ${packed} |
| Files listed in skipped manifest | ${SKIPPED_MANIFEST_COUNT} |
| Files skipped while packing | ${skipped} |
| Encoding | UTF-8 |
GITINFO

echo ""
echo "Done!"
echo "  Output: $OUTPUT_FILE"
echo "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "  Files: $packed packed, $SKIPPED_MANIFEST_COUNT listed in skipped manifest, $skipped skipped while packing"
echo "  Profile: $PROFILE"
