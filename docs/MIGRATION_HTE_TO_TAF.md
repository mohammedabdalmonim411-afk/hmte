# Migration: HTE → TriAgentFlow / TAF

**Date**: 2026-06-10  
**Status**: Current public name migrated; CLI prefix retained for compatibility

## Summary

The project formerly known as **HTE / Hermes Team Engine** is now publicly named **TriAgentFlow / TAF**.

## Name Changes

| Aspect | Old | New |
|--------|-----|-----|
| Public full name | HTE / Hermes Team Engine | TriAgentFlow |
| Public abbreviation | HTE | TAF |
| Chinese positioning | 多 Agent 工程协作治理协议 | 三角色智能体开发工作流 |
| Current version title | Historical HTE v2.0 references | TriAgentFlow / TAF v2.0 |
| Audit pack prefix | HTE_v2.0_* | TAF_v2.0_* |

## What Changed

- All public-facing documents (README, HERMES, project plan, validation summary)
- All `docs/` headers and metadata
- Audit pack headers and filenames
- Script help text and comments (where visible to external users)
- CHANGELOG, CONTRIBUTING notices

## What Did NOT Change

### hmte Legacy Command Prefix

The `hmte-*` script prefix and `src/skills/hmte/` directory path are **intentionally retained** for backward compatibility:

```bash
scripts/hmte-eval.sh          # ✅ unchanged
scripts/hmte-release-gate.sh  # ✅ unchanged
scripts/hmte-plan-contract.sh # ✅ unchanged
src/skills/hmte/               # ✅ unchanged
```

**Reason**: CLI renaming would break all existing integrations, skill installs, and script invocations. The `hmte` prefix is documented as a **legacy internal prefix kept for backward compatibility**. A future version may introduce `taf` CLI alongside `hmte`, but this is not part of the current migration.

### Legacy Internal Codename Removal

The legacy internal codename has been removed from public files. Historical platform migration notes must use generic legacy labels rather than the codename.

### HTE as Historical Reference

"HTE" and "Hermes Team Engine" may appear only as:
- `*Formerly HTE / Hermes Team Engine.*` in document headers
- Historical changelog entries
- Migration notes (this document)
- Historical version references (v1.9 project plan, roadmap)
- Legacy command prefix notes (`hmte-*`)

HTE must NOT appear as the current primary name in any public-facing document.

## Why Scripts and Directories Are Not Renamed Now

The repository intentionally keeps `hmte-*` scripts and `src/skills/hmte/` paths for compatibility. Renaming them in v2.0 would break existing local scripts, skill installs, audit fixtures, and eval cases while adding no protocol value.

Future CLI naming (`taf-*` alongside or instead of `hmte-*`) is a separate compatibility decision and is not part of this migration.

## Verification

After migration, run:
```bash
# Verify no HTE as current name in public docs
grep -rn "HTE v2.0\|HTE v2.1\|HTE protocol\|HTE workflow" README.md HERMES.md docs/ --include='*.md' | grep -v "Formerly"

# Verify no legacy internal codename remains
grep -Rni "<legacy-codename-pattern>" . --exclude-dir=.git
```
