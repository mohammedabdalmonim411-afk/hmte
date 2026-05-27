# .claude/ Directory - Legacy Structure

⚠️ **DEPRECATED FOR HERMES USERS** ⚠️

## What is this directory?

This directory contains the **original Claude Code project structure** for HTE (Hermes Team Engine). It is preserved for:

1. **Historical reference** - Shows the original implementation
2. **Backward compatibility** - Claude Code users can still use this structure
3. **Documentation** - Complete skill implementation is visible
4. **Git history** - Maintains clean version control

## For Hermes Users

**Do NOT use this directory directly with Hermes.**

Hermes uses a **global profile-based architecture** where skills are installed to:

```
~/.hermes/profiles/<profile>/skills/<skill-name>/
```

### Installation for Hermes

Run the installation script from the project root:

```bash
./install-to-hermes.sh
```

This will copy the skill files to your Hermes profile:

```
~/.hermes/profiles/default/skills/hmte/
├── SKILL.md
├── agents/
├── hooks/
├── scripts/
├── evidence-schema.json
├── audit-checklist.md
└── phase-template.md
```

## For Claude Code Users

If you're using Claude Code, this directory structure works as-is:

```
.claude/
├── skills/
│   └── mavis-team-engine/
│       └── SKILL.md
├── agents/
│   ├── master-planner.md
│   ├── phase-executor.md
│   └── verifier.md
└── hooks/
    ├── pretool_guard.sh
    ├── stop_gate.sh
    └── task_naming.sh
```

Claude Code will automatically discover skills from this directory.

## Directory Structure

### skills/mavis-team-engine/

The main skill definition and supporting files:

- **SKILL.md** - Main skill definition (entry point)
- **phase-template.md** - Template for phase definitions
- **evidence-schema.json** - JSON schema for evidence bundles
- **audit-checklist.md** - Verifier checklist
- **scripts/** - Helper scripts for state management and evidence collection

### agents/

Agent definitions for the three-role system:

- **master-planner.md** - Leader agent (planning, state management)
- **phase-executor.md** - Worker agent (implementation, evidence)
- **verifier.md** - Auditor agent (verification, verdicts)

### hooks/

Safety and enforcement hooks:

- **pretool_guard.sh** - Blocks dangerous commands
- **stop_gate.sh** - Prevents stopping with incomplete work
- **task_naming.sh** - Enforces task naming conventions

⚠️ **Note**: These hooks are **only executed by Claude Code**. Hermes does not automatically execute project-level hooks. For Hermes, safety enforcement is handled through the skill's instructions and agent definitions.

## Platform Differences

| Aspect | Claude Code | Hermes |
|--------|-------------|--------|
| **Skill Location** | `.claude/skills/` (project-local) | `~/.hermes/profiles/<profile>/skills/` (global) |
| **Discovery** | Automatic from project | Automatic from profile |
| **Scope** | Per-project | Cross-project |
| **Installation** | Copy to project | Run install script |

## Migration Path

If you're migrating from Claude Code to Hermes:

1. ✅ Keep this `.claude/` directory (for reference)
2. ✅ Run `./install-to-hermes.sh` (installs to profile)
3. ✅ Use the skill in Hermes (invokes from profile)
4. ✅ `.phase_control/` stays project-local (unchanged)

## Why Keep This Directory?

**Reasons for preservation:**

1. **Documentation** - Complete implementation is visible in the repo
2. **Portability** - Project can work with both platforms
3. **Reference** - Developers can see the full skill structure
4. **History** - Git history remains clean and understandable
5. **Compatibility** - Claude Code users can still use the project

**Not removed because:**

- No technical reason to delete it
- Provides valuable reference
- Maintains backward compatibility
- Costs nothing to keep

## Runtime State

**Important**: Runtime state (`.phase_control/`) is **NOT** in this directory.

Runtime state is **project-local** on both platforms:

```
project-root/
├── .claude/              # Skill definitions (legacy)
└── .phase_control/       # Runtime state (active)
    ├── state.json
    ├── phases.yaml
    ├── evidence/
    └── verdicts/
```

This ensures each project has isolated state.

## See Also

- [PLATFORM_HISTORY.md](../PLATFORM_HISTORY.md) - Detailed migration history
- [install-to-hermes.sh](../install-to-hermes.sh) - Hermes installation script
- [README.md](../README.md) - Main project documentation

## Questions?

**Q: Should I delete this directory?**  
A: No, keep it for reference and compatibility.

**Q: Will Hermes use this directory?**  
A: No, Hermes uses `~/.hermes/profiles/<profile>/skills/`.

**Q: Can I still use Claude Code?**  
A: Yes, this structure works with Claude Code.

**Q: Do I need to update this directory?**  
A: No, it's frozen as a reference. Updates go to the Hermes profile.

---

**Status**: DEPRECATED for Hermes, MAINTAINED for Claude Code  
**Last Updated**: 2026-05-27  
**Migration**: Use `install-to-hermes.sh` for Hermes installation
