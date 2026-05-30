# Changelog

All notable changes to HTE (Hermes Team Engine) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] - 2026-05-30

### Added
- **Leader Jail** — 项目面改动必须有完整 ownership chain（evidence + receipt + command log + verdict + phase_gate）
- **Goalpost Lock** — SHA256 锁定验收标准，检测后续弱化/删除/新增 phase
- **Instruction Lint** — 检测"只检查格式"类危险弱化语句
- **Evidence Claim Verification** — 验证每个 claimed file 真实存在 + 在 git diff 中 + 在 command log 中
- **Verifier Minimum Audit** — 强制 verdict 包含 independently_verified_files 和 re_verification_conclusion
- **Final Check v2** — 完整链路检查（7-file 完整性 + 全部 P0 检查 + Leader Jail）
- **Profile/Global Dual-Path Installer** — install-to-hermes.sh 支持 --profile 和 --all 模式
- **E2E P0 Hardening Tests** — 新增 T1-T10 覆盖 Leader Jail、Goalpost Lock、新增 phase 检查

### Changed
- README / HERMES / SKILL 统一到 v1.4 工作流（install → kickoff → goal lock → final-check release）
- final-check 现在是主流程门禁，未通过的完成声明视为无效
- hmte-verify-claims.sh 现在覆盖 working tree + staged + committed + untracked 改动（与 Leader Jail 一致）
- Goalpost Lock 现在检测新增 phase，release 模式下要求 amendment 授权

### Security
- 硬化项目面 ownership chain，Leader 不能直接改项目文件
- 阻止弱化 instruction patterns（"只检查格式"、"不运行测试"等）
- 阻止 goalpost weakening（删除 criteria、删除 phase、新增弱 phase）
- release 模式下 WARN 升级为 FAIL，缺 goal_lock/final_audit/leader-jail 均 FAIL

## [1.2.0] - 2026-05-28

### Added
- Initial release of HTE (Hermes Team Engine)
- Leader/Worker/Verifier multi-agent architecture
- Phase-based workflow with quality gates
- Evidence-driven verification system
- State machine tracking with `.phase_control/state.json`
- Safety enforcement with pretool guards and stop gates
- Cross-platform support (Linux, macOS, Windows with Git Bash)
- Comprehensive documentation and examples
- E2E testing framework
- Installation script for Hermes integration
- MIT License

### Changed
- Migrated from Claude Code to Hermes Agent platform
- Renamed from "Mavis Team Engine" to "HTE (Hermes Team Engine)"
- Updated all agent definitions to Hermes format
- Consolidated all scripts with `hmte-` prefix
- Improved Windows compatibility (fcntl fallback, python vs python3)

### Fixed
- Windows compatibility issues with file locking
- Python command compatibility across platforms
- JSON validation fallback when jq is not available
- Documentation references to outdated platform names
- Badge links in README
- Manual testing step numbering

### Security
- Input validation in all shell scripts
- Command injection prevention in evidence collection
- Safe file operations with proper escaping

---

## Version History Notes

This project was originally developed as "Mavis Team Engine" for Claude Code and has been migrated to Hermes Agent. Historical documentation and implementation details can be found in `docs/history/`.

For migration details, see:
- `docs/history/PLATFORM_HISTORY.md`
