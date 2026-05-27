# Changelog

All notable changes to HTE (Hermes Team Engine) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed
- Migrated from Claude Code to Hermes Agent platform
- Renamed from "Mavis Team Engine" to "HTE (Hermes Team Engine)"
- Updated all agent definitions to Hermes format
- Consolidated scripts with `hmte-` prefix (with `mavis-` compatibility wrappers)
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

## [1.0.0] - 2026-05-27

### Added
- First stable release
- Production-ready multi-agent workflow system
- Complete documentation suite
- MIT License

---

## Version History Notes

This project was originally developed as "Mavis Team Engine" for Claude Code and has been migrated to Hermes Agent. Historical documentation and implementation details can be found in `docs/history/`.

For migration details, see:
- `docs/history/MIGRATION_COMPLETE.md`
- `docs/history/PLATFORM_HISTORY.md`
- `docs/history/IMPLEMENTATION_SUMMARY.md`
