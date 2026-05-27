# File Naming Conventions

This document describes the file naming conventions used in the HTE (Hermes Team Engine) project.

## Current State

The project uses a mix of naming conventions due to its evolution from Claude Code to Hermes:

### Uppercase (SCREAMING_SNAKE_CASE)
Used for important documentation and configuration files:
- `README.md`
- `LICENSE`
- `CHANGELOG.md`
- `CONTRIBUTING.md` (if added)
- `CODE_OF_CONDUCT.md` (if added)

### lowercase with hyphens (kebab-case)
Used for scripts and executable files:
- `install-to-hermes.sh`
- `hmte-start.sh`
- `hmte-stop.sh`
- `hmte-status.sh`
- `hmte-e2e.sh`
- `collect_evidence.sh` (uses underscore for historical reasons)
- `write_state.py` (Python convention)

### Mixed case
Used for historical/legacy documentation:
- `AUDIT_REPORT.md`
- `VERIFICATION_REPORT.md`
- `IMPLEMENTATION_SUMMARY.md`
- `MIGRATION_COMPLETE.md`

### Directories
- `.phase_control/` - lowercase with underscore
- `docs/` - lowercase
- `scripts/` - lowercase
- `src/` - lowercase

## Rationale

The mixed conventions reflect:

1. **Standard conventions**: Top-level docs like README, LICENSE follow common open-source conventions (uppercase)
2. **Shell script conventions**: Executable scripts use lowercase with hyphens for readability
3. **Python conventions**: Python files use lowercase with underscores (PEP 8)
4. **Historical artifacts**: Some files retain their original naming from the Claude Code era

## Recommendations for New Files

When adding new files to the project:

- **Top-level documentation**: Use UPPERCASE (e.g., `SECURITY.md`, `CONTRIBUTING.md`)
- **Shell scripts**: Use lowercase with hyphens (e.g., `hmte-new-feature.sh`)
- **Python scripts**: Use lowercase with underscores (e.g., `new_utility.py`)
- **Markdown docs in subdirectories**: Use lowercase with hyphens or underscores (e.g., `user-guide.md`, `api_reference.md`)
- **Directories**: Use lowercase, prefer hyphens for multi-word names

## No Planned Renaming

We do not plan to rename existing files for consistency because:

1. It would break existing scripts and references
2. Git history would be harder to follow
3. Users may have local modifications
4. The mixed conventions are well-documented and don't cause functional issues

If you're forking this project and want consistent naming, consider doing a bulk rename as your first commit.
