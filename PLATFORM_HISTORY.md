# Platform Migration History

## Overview

HMTE (Hermes Mavis Team Engine) was originally developed for **Claude Code** and has been migrated to **Hermes**. This document explains the architectural differences between the two platforms and why certain directory structures are preserved.

## Timeline

- **2026-05-26**: Initial development on Claude Code platform
- **2026-05-27**: Migration to Hermes platform
- **Current**: Dual-platform support with Hermes as primary target

## Platform Architecture Differences

### Claude Code Architecture

Claude Code uses a **project-local** architecture:

```
project/
├── .claude/
│   ├── skills/
│   │   └── <skill-name>/
│   │       └── SKILL.md
│   ├── agents/
│   │   ├── master-planner.md
│   │   ├── phase-executor.md
│   │   └── verifier.md
│   └── hooks/
│       ├── pretool_guard.sh
│       ├── stop_gate.sh
│       └── task_naming.sh
└── .phase_control/
    └── (runtime state)
```

**Characteristics:**
- Skills and agents are stored **within each project**
- Each project has its own `.claude/` directory
- Skills are project-specific by default
- No global skill registry

### Hermes Architecture

Hermes uses a **global profile-based** architecture:

```
~/.hermes/
└── profiles/
    └── <profile-name>/
        ├── skills/
        │   └── <skill-name>/
        │       └── SKILL.md
        ├── plugins/
        └── memories/

project/
└── .phase_control/
    └── (runtime state)
```

**Characteristics:**
- Skills are stored **globally** in user profile
- Skills are available across all projects
- Profile-based isolation (default, work, personal, etc.)
- Centralized skill management

## Migration Strategy

### Why We Keep `.claude/` Directory

The `.claude/` directory is **preserved for historical and compatibility reasons**:

1. **Documentation**: Shows the original Claude Code structure
2. **Reference**: Developers can see the complete skill implementation
3. **Portability**: Project can still work with Claude Code if needed
4. **Git History**: Maintains clean git history without massive restructuring

### Hermes Installation

For Hermes users, skills must be installed to the global profile:

```bash
# Install to Hermes profile
./install-to-hermes.sh

# Skills are copied to:
~/.hermes/profiles/default/skills/hmte/
```

## Key Differences in Usage

### Claude Code Usage

```bash
# Skills are automatically discovered from .claude/skills/
# Just use the skill name in conversation
```

### Hermes Usage

```bash
# Skills must be installed to profile first
./install-to-hermes.sh

# Then use the skill name in conversation
# Hermes loads from ~/.hermes/profiles/default/skills/
```

## File Path References

Throughout the codebase, you may see references to `.claude/` paths. These should be understood as:

| Legacy Path (Claude Code) | Hermes Equivalent |
|---------------------------|-------------------|
| `.claude/skills/mavis-team-engine/` | `~/.hermes/profiles/default/skills/hmte/` |
| `.claude/agents/` | `~/.hermes/profiles/default/skills/hmte/agents/` |
| `.claude/hooks/` | `~/.hermes/profiles/default/skills/hmte/hooks/` |
| `.phase_control/` | `.phase_control/` (unchanged, project-local) |

## Runtime State Location

**Important**: Runtime state (`.phase_control/`) remains **project-local** on both platforms:

```
project/
└── .phase_control/
    ├── state.json          # Current phase state
    ├── phases.yaml         # Phase definitions
    ├── evidence/           # Evidence bundles
    ├── verdicts/           # Verification verdicts
    └── run.lock            # Session lock
```

This ensures:
- Each project has isolated state
- No cross-project contamination
- State travels with the project in git

## Migration Checklist

If you're migrating from Claude Code to Hermes:

- [x] Run `./install-to-hermes.sh` to install skills
- [x] Verify skills appear in `~/.hermes/profiles/default/skills/hmte/`
- [x] Update any hardcoded `.claude/` paths in your scripts
- [x] Test skill invocation in Hermes
- [x] Verify `.phase_control/` state management still works

## Backward Compatibility

The project maintains backward compatibility with Claude Code:

1. `.claude/` directory is fully functional
2. All scripts work with both platforms
3. Documentation covers both platforms
4. No breaking changes to core functionality

## Future Direction

**Primary Platform**: Hermes
- All new development targets Hermes
- Documentation prioritizes Hermes usage
- Claude Code support is maintained but not primary

**Deprecation Timeline**:
- `.claude/` directory: Maintained indefinitely for reference
- Claude Code support: No planned deprecation
- Dual-platform support: Ongoing

## Technical Notes

### Skill Discovery

**Claude Code**: Scans `.claude/skills/` in project directory
**Hermes**: Scans `~/.hermes/profiles/<profile>/skills/` globally

### Agent Definitions

**Claude Code**: Agents defined in `.claude/agents/*.md`
**Hermes**: Agents embedded in skill or defined in profile

### Hooks

**Claude Code**: Hooks in `.claude/hooks/` auto-discovered
**Hermes**: Hooks must be registered in skill manifest

### State Management

Both platforms use the same state management:
- `.phase_control/state.json` (Leader-only)
- File locking with `fcntl` (Python) or `noclobber` (Bash)
- Atomic writes for race condition prevention

## Questions?

- **Why not remove `.claude/`?** - Historical reference and backward compatibility
- **Can I use both platforms?** - Yes, but install to Hermes profile first
- **Which platform is better?** - Hermes is the primary target going forward
- **Will Claude Code support be dropped?** - No current plans to drop support

## See Also

- [README.md](README.md) - Installation instructions for both platforms
- [install-to-hermes.sh](install-to-hermes.sh) - Hermes installation script
- [.claude/README.md](.claude/README.md) - Legacy directory explanation
