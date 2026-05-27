# HTE (Hermes Team Engine)

> A Hermes-native multi-agent development system implementing the Leader/Worker/Verifier pattern for rigorous, phase-based software development.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-green.svg)

> **📝 Platform Migration Note**: This project was originally developed for Claude Code and has been migrated to Hermes Agent. References to "Claude Code" throughout the documentation are for legacy support and format compatibility. New users should follow the Hermes installation instructions. See [PLATFORM_HISTORY.md](docs/history/PLATFORM_HISTORY.md) for migration details.

> **📝 Repository Name Note**: This repository is currently named `mavis-team-engine` for historical reasons. The recommended name is `hmte` (Hermes Team Engine). If you're forking or cloning, consider renaming it to `hmte` for consistency with the project's current branding.

> **📝 Note**: This README contains template GitHub URLs (github.com/YOUR_USERNAME/mavis-team-engine). When using this project, replace `YOUR_USERNAME` with your actual GitHub username or remove references if not publishing to GitHub.

## ⚠️ Disclaimer

This project is an independent open-source community implementation.

### Trademark Notice

- **"Mavis"** is a registered trademark of MiniMax Technology Limited. In this project, "Mavis" refers **solely to the architectural pattern** (Leader/Worker/Verifier) described in MiniMax's research papers as inspiration for this implementation. This is **NOT** an official MiniMax product, is **NOT** endorsed by MiniMax, has **NO** affiliation with MiniMax, and does **NOT** imply any commercial relationship. The use of "Mavis" is purely descriptive and refers to the architectural concept, not the trademark.

  **⚠️ TRADEMARK RISK WARNING**: Using "Mavis" in the repository name or branding may create trademark confusion. This is a **community project** with **no authorization** from MiniMax. If you fork or deploy this project, consider using a different name (e.g., "HTE", "Hermes Team Engine") to avoid potential trademark issues. The maintainers of this project make no claims to the "Mavis" trademark and recommend users consult legal counsel before using this name in commercial contexts.

- **"Hermes"** is developed by Nous Research. This project is a third-party tool and is not affiliated with, endorsed by, or sponsored by Nous Research

- This project is provided "as-is" under the MIT License with no warranties

**All trademarks are the property of their respective owners. Use of trademarked names is for descriptive and educational purposes only and does not imply endorsement, affiliation, or sponsorship. Users assume all responsibility for trademark compliance when forking, deploying, or distributing this software.**

## 🎯 What is HTE?

HTE is a **production-ready framework** that brings structured, multi-agent collaboration to Hermes. Inspired by MiniMax's Mavis architecture, it enforces a rigorous "plan → execute → verify → release" cycle with:

- **Phase-based workflow** with explicit quality gates
- **Evidence-driven verification** - all decisions backed by structured proof
- **Independent quality assurance** - adversarial verification prevents rubber-stamping
- **Worktree isolation** - workers execute in isolated environments
- **State machine tracking** - explicit state management, not LLM memory
- **Safety enforcement** - command guards and permission controls

### Why Use This?

Traditional AI-assisted development often suffers from:
- ❌ No quality gates - changes go straight to production
- ❌ No verification - trust but don't verify
- ❌ Context pollution - all agents see everything
- ❌ No audit trail - can't trace decisions

HTE solves these with:
- ✅ **Mandatory verification** - nothing proceeds without PASS verdict
- ✅ **Adversarial review** - Verifier actively looks for problems
- ✅ **Context isolation** - each role sees only what it needs
- ✅ **Complete audit trail** - every decision is documented

## 🏗️ Architecture

```
User Goal
    ↓
┌─────────────────────────────────────┐
│  Leader (master-planner)            │
│  - Plans phases                     │
│  - Maintains state machine          │
│  - Dispatches work                  │
│  - Decides PASS/FAIL/BLOCK          │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Phase Plan (phases.yaml)           │
│  - Objectives & acceptance criteria │
│  - Required evidence types          │
│  - Timeout & retry policies         │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Worker (phase-executor)            │
│  - Executes in isolated worktree   │
│  - Implements changes               │
│  - Produces evidence bundle         │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Evidence Bundle (JSON)             │
│  - Changed files                    │
│  - Test results                     │
│  - Build output                     │
│  - Screenshots (frontend)           │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Verifier (independent auditor)     │
│  - Read-only access                 │
│  - Checks acceptance criteria       │
│  - Outputs PASS/FAIL/BLOCK          │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Verdict (fixed format)             │
│  - PASS → Next phase                │
│  - FAIL → Rework (retry)            │
│  - BLOCK → Escalate                 │
└─────────────────────────────────────┘
```

### Three Core Roles

| Role | Model | Permissions | Responsibility |
|------|-------|-------------|----------------|
| **Leader** (master-planner) | Opus | Full | Plans phases, dispatches work, maintains state machine |
| **Worker** (phase-executor) | Sonnet | Read/Write/Execute | Implements changes in isolated worktree, produces evidence |
| **Verifier** | Opus | Read-only | Independently audits evidence, outputs verdict |

### Key Mechanisms

- **Phase Gates**: No phase proceeds without PASS verdict
- **Evidence Bundles**: Structured JSON with all execution artifacts
- **Adversarial Verification**: Verifier actively seeks problems
- **Context Isolation**: Each role sees minimal necessary context
- **State Machine**: Explicit state tracking in `.phase_control/state.json`
- **Worktree Isolation**: Workers execute in separate git worktrees
- **Automatic Retry**: FAIL triggers rework with attempt counter
- **Safety Hooks**: Command guards prevent dangerous operations

## 🚀 Quick Start

### Prerequisites

> **⚠️ Platform Compatibility**: Currently tested on Unix/Linux/macOS. Windows support is experimental and requires:
> - Git Bash or WSL for shell scripts
> - Python `filelock` library: `pip install filelock`
> - Some features may have limited functionality on Windows

- **Hermes** (CLI, Desktop, or Web)
- **Python 3.8+**
- **Git**
- **Bash** (Unix-like shell)

> **⚠️ Platform Compatibility**: This project is designed for Unix-like systems (Linux, macOS). Windows users can use WSL (Windows Subsystem for Linux) or Git Bash, though some scripts may require adjustments. The core Hermes skill works cross-platform, but shell scripts assume a Unix environment.

### Installation

## 🚀 Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/mavis-team-engine.git
cd mavis-team-engine
```

> **📝 Note**: The GitHub URL above is a template. If you're using a fork or different repository, replace it with your actual repository URL.

2. **Install to Hermes profile:**

```bash
./install-to-hermes.sh
```

This installs the skill to `~/.hermes/profiles/default/skills/hmte/` where Hermes can discover it globally.

3. **Copy runtime structure to your project:**

```bash
# Navigate to your project directory
cd /path/to/your/project

# Copy the runtime structure from the cloned repository
# If you cloned to ~/mavis-team-engine:
cp -r ~/mavis-team-engine/.phase_control .
cp -r ~/mavis-team-engine/scripts .
```

> **📝 Note**: Replace `~/mavis-team-engine` with the actual path where you cloned the repository. Common examples:
> - Linux/macOS: `~/projects/mavis-team-engine`
> - Windows (Git Bash): `/c/Users/YourName/mavis-team-engine`
> - Or use absolute paths like `/home/username/mavis-team-engine`

4. **Initialize the session:**

```bash
./scripts/mavis-start.sh
```

5. **Use in Hermes:**

```
Please use the hmte skill to implement user authentication.
```

#### For Claude Code Users (Legacy)

1. **Clone or copy to your project:**

```bash
# Option 1: Clone as a submodule
git submodule add https://github.com/YOUR_USERNAME/mavis-team-engine .mavis

# Option 2: Copy directly
cp -r /path/to/mavis-team-engine/.claude .
cp -r /path/to/mavis-team-engine/.phase_control .
cp -r /path/to/mavis-team-engine/scripts .
```

2. **Initialize the session:**

```bash
./scripts/mavis-start.sh
```

3. **Use in Claude Code:**

```
Please use the mavis-team-engine skill to implement user authentication.
```

> **Note**: See [PLATFORM_HISTORY.md](PLATFORM_HISTORY.md) for details on platform differences.

### ⚠️ Platform Compatibility

#### Hooks (.claude/hooks/*.sh)
The hooks in `.claude/hooks/` are **Claude Code specific** and will NOT automatically execute in Hermes Agent:

- **Claude Code**: Hooks (`pretool_guard.sh`, `stop_gate.sh`, `task_naming.sh`) are automatically triggered before tool execution
- **Hermes Agent**: Hooks are NOT automatically executed and must be manually integrated

**For Hermes users:**
- The hooks are provided as reference implementations
- You can manually call them in your workflow scripts
- Hermes has its own built-in safety features
- Review commands manually before execution for safety-critical operations

#### Agent Definitions (.claude/agents/*.md)
The agent definition files use **Claude Code format**:

- **Claude Code**: Uses `subagent_type`, `permissionMode`, `isolation`, etc.
- **Hermes Agent**: Use `delegate_task` instead when calling sub-agents

Refer to `.claude/skills/mavis-team-engine/SKILL.md` for Hermes-compatible patterns.

### Verification

Run the end-to-end test to verify installation:

```bash
./scripts/mavis-e2e.sh
```

Expected output:
```
=== E2E Test PASSED ===

Verified:
  ✓ Session initialization
  ✓ Phase definition
  ✓ Evidence bundle creation
  ✓ Verdict format
  ✓ State management
  ✓ Stop gate enforcement
```

## 📖 Usage

### Basic Workflow

1. **Start a session:**
```bash
./scripts/mavis-start.sh
```

2. **Invoke the skill in Hermes:**
```
Please use the mavis-team-engine skill to implement a login API with JWT authentication.
```

3. **The system will:**
   - Leader analyzes requirements and creates phase plan
   - For each phase:
     - Worker executes in isolated worktree
     - Worker produces evidence bundle
     - Verifier audits evidence
     - Leader decides: PASS → next phase, FAIL → rework, BLOCK → escalate
   - Continues until all phases complete

4. **Check status anytime:**
```bash
./scripts/mavis-status.sh
```

5. **Stop when done:**
```bash
./scripts/mavis-stop.sh
```

### Example Workflow: What Happens When You Request User Authentication

> **⚠️ Important**: The following is a **workflow demonstration example** showing how the system operates. This is NOT actual implemented functionality in the repository. The example illustrates the phase-based workflow pattern, not real code that exists in this project.

**User request:**
```
Please use the mavis-team-engine skill to implement user authentication with:
- Login API endpoint
- JWT token generation
- Password hashing with bcrypt
- Unit tests with >80% coverage
```

**What happens:**

1. **Leader creates phase plan:**
   - Phase A: Requirements analysis and API design
   - Phase B: Backend implementation
   - Phase C: Test implementation
   - Phase D: Integration testing
   - Phase E: Final verification

2. **Phase A execution:**
   - Worker creates design document
   - Worker produces evidence bundle
   - Verifier checks: design complete? requirements clear?
   - Verdict: PASS → proceed to Phase B

3. **Phase B execution:**
   - Worker implements login API in isolated worktree
   - Worker runs tests, collects results
   - Worker produces evidence bundle with:
     - Changed files: `src/api/auth.js`
     - Test results: 5 passed, 0 failed
     - Build results: success
   - Verifier checks:
     - ✓ JWT token generation works
     - ✓ bcrypt used for passwords
     - ✓ Tests pass
     - ✗ Coverage only 65% (needs 80%)
   - Verdict: FAIL → return to Worker

4. **Phase B retry:**
   - Worker adds more tests
   - Coverage now 85%
   - Verifier checks again
   - Verdict: PASS → proceed to Phase C

5. **Continues until all phases complete**

### Evidence Bundle Format

Every phase execution produces a structured JSON evidence bundle:

```json
{
  "phase_id": "phase_b",
  "attempt": 1,
  "worker_name": "phase-executor",
  "goal_summary": "Implement login API",
  "changed_files": ["src/api/auth.js", "tests/auth.test.js"],
  "commands_run": ["npm install", "npm test"],
  "command_exit_codes": [0, 0],
  "test_results": {
    "total": 5,
    "passed": 5,
    "failed": 0,
    "skipped": 0
  },
  "build_results": {
    "success": true,
    "errors": []
  },
  "unresolved_risks": ["JWT secret needs production config"],
  "verification_gaps": ["Concurrent login not tested"],
  "generated_at": "2026-05-26T12:00:00Z"
}
```

### Verdict Format

Verifier outputs one of three fixed-format verdicts:

**PASS:**
```
VERDICT: PASS
PHASE_ID: phase_b
CONFIDENCE: high
ACCEPTANCE_CHECKS:
- [x] JWT token generation works
- [x] Password hashing with bcrypt
- [x] Unit tests pass
- [x] Coverage > 80%
RESIDUAL_RISKS:
- JWT secret needs production configuration
EVIDENCE_USED:
- .phase_control/evidence/phase_b_attempt_1.json
NEXT_ACTION: RELEASE_TO_NEXT_PHASE
```

**FAIL:**
```
VERDICT: FAIL
PHASE_ID: phase_b
CONFIDENCE: high
FAILED_CHECKS:
- [ ] Test coverage only 65%, needs 80%
ROOT_CAUSES:
- Missing edge case tests
REQUIRED_REWORK:
- Add tests for empty password, weak password, special characters
- Ensure coverage > 80%
EVIDENCE_USED:
- .phase_control/evidence/phase_b_attempt_1.json
NEXT_ACTION: RETURN_TO_EXECUTOR
```

**BLOCK:**
```
VERDICT: BLOCK
PHASE_ID: phase_b
CONFIDENCE: high
BLOCKERS:
- Missing database configuration
- Cannot run tests
MISSING_INPUTS:
- database.config.js
- .env file
SAFE_OPTIONS:
- Create default database.config.js
- Provide .env.example template
EVIDENCE_USED:
- .phase_control/evidence/phase_b_attempt_1.json
NEXT_ACTION: ESCALATE_TO_LEADER
```

## 📁 Project Structure

### Repository Structure

```
.
├── .claude/                            # Legacy Claude Code structure (see .claude/README.md)
│   ├── skills/mavis-team-engine/
│   │   ├── SKILL.md                    # Main skill definition
│   │   ├── phase-template.md           # Phase definition template
│   │   ├── evidence-schema.json        # Evidence bundle JSON schema
│   │   ├── audit-checklist.md          # Verifier checklist
│   │   └── scripts/
│   │       ├── write_state.py          # State management (with file locking)
│   │       ├── phase_gate.sh           # Phase transition logic
│   │       └── collect_evidence.sh     # Evidence collection
│   ├── agents/                         # Claude Code agent definitions
│   │   ├── master-planner.md           # Leader agent
│   │   ├── phase-executor.md           # Worker agent
│   │   └── verifier.md                 # Auditor agent
│   └── hooks/                          # Claude Code hooks (NOT executed by Hermes)
│       ├── pretool_guard.sh            # Command safety checks
│       ├── stop_gate.sh                # Incomplete work prevention
│       └── task_naming.sh              # Task naming enforcement
├── .phase_control/                     # Runtime state (project-local)
│   ├── phases.yaml                     # Phase definitions
│   ├── state.json                      # State machine (Leader-only)
│   ├── current_phase                   # Current phase ID
│   ├── run.lock                        # Session lock file
│   ├── evidence/                       # Evidence bundles (JSON)
│   ├── verdicts/                       # Verification verdicts (TXT)
│   ├── logs/                           # JSONL logs
│   ├── pids/                           # Process IDs
│   └── traces/                         # Performance traces
├── scripts/
│   ├── mavis-start.sh                  # Initialize session
│   ├── mavis-stop.sh                   # Stop session
│   ├── mavis-status.sh                 # Show status
│   └── mavis-e2e.sh                    # End-to-end test
├── install-to-hermes.sh                # Hermes installation script
├── PLATFORM_HISTORY.md                 # Platform migration history
├── HERMES.md                           # Project rules
├── README.md                           # This file
├── LICENSE                             # MIT License
└── .gitignore                          # Git ignore rules
```

### Hermes Installation Structure

After running `./install-to-hermes.sh`, skills are installed to:

```
~/.hermes/profiles/default/skills/hmte/
├── SKILL.md                            # Main skill definition
├── agents/
│   ├── master-planner.md
│   ├── phase-executor.md
│   └── verifier.md
├── hooks/
│   ├── stop_gate.sh
│   ├── pretool_guard.sh
│   └── task_naming.sh
├── scripts/
│   ├── write_state.py
│   ├── collect_evidence.sh
│   └── phase_gate.sh
├── phase-template.md
├── evidence-schema.json
└── audit-checklist.md
```

> **Note**: `.phase_control/` remains **project-local** on both platforms. Only skill definitions move to the Hermes profile.

## 🔒 Security Features

### Implemented Security Fixes

All critical vulnerabilities have been fixed:

1. **✅ State File Race Condition** - Atomic writes with fcntl file locking
2. **✅ Path Traversal** - Strict regex validation of all path components
3. **✅ JSON Injection** - Python json.dump() instead of heredoc
4. **✅ Lock File Race** - Atomic lock creation with bash noclobber
5. **✅ Command Injection** - Multi-layered pattern detection

### Safety Mechanisms

- **Command Guards**: `pretool_guard.sh` blocks dangerous commands:
  - `rm -rf` on system paths
  - Filesystem operations (`mkfs`, `format`)
  - Privilege escalation (`sudo`, `su`)
  - Network exfiltration patterns
  
- **Stop Gate**: `stop_gate.sh` prevents stopping with incomplete work:
  - Blocks if phase status != passed
  - Blocks if background services running
  - Blocks if evidence without verdict

- **Worktree Isolation**: Workers execute in separate git worktrees

- **Read-only Verifier**: Verifier has no Edit/Write permissions

## ⚙️ Configuration

### Model Strategy

Default model assignments (configurable in agent frontmatter):

- **Leader**: Opus (planning requires deep reasoning)
- **Worker**: Sonnet (execution is well-scoped)
- **Verifier**: Opus (verification requires skepticism)

To change models, edit the agent definition files:

**For Hermes users:**
```bash
# Edit in your Hermes profile
nano ~/.hermes/profiles/default/skills/hmte/agents/phase-executor.md
```

**For Claude Code users:**
```bash
# Edit in project directory
nano .claude/agents/phase-executor.md
```

Agent frontmatter example:
```yaml
---
name: phase-executor
model: opus  # Change from sonnet to opus
---
```

### Timeout & Retry Policies

Configure per-phase in `.phase_control/phases.yaml`:

```yaml
- id: phase_b
  timeout_soft: 600      # 10 minutes (warning)
  timeout_hard: 1200     # 20 minutes (force stop)
  max_retries: 2         # Maximum retry attempts
  escalation_rule: "连续2次FAIL升级到Leader重规划"
```

### Permission Mode

Configure in agent frontmatter:

```yaml
---
name: master-planner
permissionMode: plan     # plan | acceptEdits | dontAsk
---
```

## 🧪 Testing

### Run End-to-End Test

```bash
./scripts/mavis-e2e.sh
```

Tests verify:
- Session initialization
- Phase definition
- Evidence bundle creation
- Verdict format
- State management
- Stop gate enforcement

### Manual Testing

1. Start session: `./scripts/mavis-start.sh`
2. Create test phase in `.phase_control/phases.yaml`
3. Invoke skill in Hermes
4. Check status: `./scripts/mavis-status.sh`
5. Verify evidence in `.phase_control/evidence/`
6. Verify verdicts in `.phase_control/verdicts/`
7. Stop session: `./scripts/mavis-stop.sh`

## 📊 Performance

### Token Costs

Multi-agent workflows consume approximately **5-10x** normal conversation tokens (estimated based on architectural overhead, not measured):
- Leader planning: ~2x (estimated)
- Worker execution: ~3x (estimated)
- Verifier audit: ~2x (estimated)

> **Note**: These are rough estimates based on the multi-agent architecture pattern. Actual token usage will vary significantly based on task complexity, model choice, and phase design. No systematic measurements have been performed.

**Optimization tips:**
- Use Sonnet for Worker (cheaper, still capable)
- Keep phases focused and small
- Provide clear acceptance criteria
- Use evidence bundles instead of full context

### Execution Time

Typical phase execution (estimated based on typical usage, not measured):
- Simple phase (add function): ~2-5 minutes
- Medium phase (implement API): ~5-15 minutes
- Complex phase (full feature): ~15-30 minutes

> **Note**: These are approximate time ranges based on typical development patterns. Actual execution time depends heavily on task complexity, model performance, network latency, and whether retries are needed.

Includes: planning, execution, evidence collection, verification, and potential retry.

## 🛠️ Troubleshooting

### Session won't start

**Error**: `Team Engine is already running`

**Solution**:
```bash
# Check if process is actually running
ps aux | grep mavis

# If not running, remove stale lock
rm .phase_control/run.lock

# Try again
./scripts/mavis-start.sh
```

### Verifier always outputs FAIL

**Cause**: Acceptance criteria too strict or evidence incomplete

**Solution**:
1. Check `.phase_control/verdicts/<phase>_attempt_<n>.txt` for FAILED_CHECKS
2. Review acceptance criteria in `.phase_control/phases.yaml`
3. Ensure Worker collects all required evidence types
4. Check if tests are actually passing

### Worker stuck in loop

**Cause**: Retry limit not reached, same error repeating

**Solution**:
1. Check `.phase_control/state.json` for `retries_used`
2. Review evidence bundles to see what's failing
3. Manually intervene or adjust `max_retries`
4. Consider BLOCK verdict if issue is environmental

### Stop gate blocks stopping

**Cause**: Phase not complete or background services running

**Solution**:
```bash
# Check status
./scripts/mavis-status.sh

# Check phase status in state.json
cat .phase_control/state.json | jq '.phase_status'

# If stuck, manually update state using write_state.py
# For Hermes users:
python3 ~/.hermes/profiles/default/skills/hmte/scripts/write_state.py \
  .phase_control/state.json phase_status=passed

# For Claude Code users:
python3 .claude/skills/mavis-team-engine/scripts/write_state.py \
  .phase_control/state.json phase_status=passed

# Or force stop (bypasses gate)
rm .phase_control/run.lock
```

## 🔄 Comparison with Other Approaches

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Single Agent** | Simple, fast, cheap | No verification, no gates | Simple tasks, prototyping |
| **Prompt-only Multi-Agent** | Easy to set up | No enforcement, roles blur | Experimentation |
| **HTE** | Enforced gates, audit trail, isolation | Higher token cost, slower | Production code, critical features |
| **External Orchestrator** | Maximum control | Complex setup, maintenance | Platform-level automation |

## 📚 Documentation

- **[PLATFORM_HISTORY.md](docs/history/PLATFORM_HISTORY.md)** - Platform migration history (Claude Code → Hermes)
- **[install-to-hermes.sh](install-to-hermes.sh)** - Hermes installation script
- **[.claude/README.md](.claude/README.md)** - Legacy directory explanation
- **[IMPLEMENTATION_PLAN.md](docs/history/IMPLEMENTATION_PLAN.md)** - Detailed design document
- **[IMPLEMENTATION_SUMMARY.md](docs/history/IMPLEMENTATION_SUMMARY.md)** - Build summary
- **[FINAL_REPORT.md](docs/history/FINAL_REPORT.md)** - Project completion report
- **[SECURITY_FIXES.md](docs/history/SECURITY_FIXES.md)** - Security improvements
- **[VERIFICATION_REPORT.md](docs/history/VERIFICATION_REPORT.md)** - Test results
- **[HERMES.md](HERMES.md)** - Project rules for Hermes

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/mavis-team-engine.git
cd mavis-team-engine

# Run tests
./scripts/mavis-e2e.sh

# Make changes
# ...

# Test changes
./scripts/mavis-start.sh
# Use in Hermes
./scripts/mavis-stop.sh
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **MiniMax** - Inspiration from Mavis architecture research paper
- **Nous Research** - Creators of Hermes AI platform. This project is a third-party tool built for Hermes and is not an official Nous Research product
- **TeamBench** - Research on multi-agent system failures
- **Community** - Feedback and contributions

This project is an independent open-source implementation and is not affiliated with, endorsed by, or sponsored by MiniMax or Nous Research.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/YOUR_USERNAME/mavis-team-engine/issues)
- **Discussions**: [GitHub Discussions](https://github.com/YOUR_USERNAME/mavis-team-engine/discussions)
- **Documentation**: [Project Wiki](https://github.com/YOUR_USERNAME/mavis-team-engine/wiki)

## 🗺️ Roadmap

### v1.1 (Planned)
- [ ] Windows compatibility improvements
- [ ] MCP browser tools integration guide
- [ ] Performance profiling tools
- [ ] Health check script

### v1.2 (Planned)
- [ ] Parallel phase execution
- [ ] Advanced retry strategies
- [ ] Metrics dashboard
- [ ] CI/CD integration examples

### v2.0 (Future)
- [ ] External orchestrator option
- [ ] Machine learning for phase planning
- [ ] Multi-project support
- [ ] Web UI for monitoring

## 📈 Project Stats

> **Note**: Statistics as of 2026-05-27. Run `find . -type f \( -name "*.sh" -o -name "*.py" -o -name "*.md" -o -name "*.json" -o -name "*.yaml" \) ! -path "./.git/*" ! -path "./.phase_control/*" | wc -l` to get current counts.

- **Lines of Code**: ~11,408 total (1,384 shell + 226 Python + 9,371 docs + 354 JSON + 73 other) *(Statistics as of 2026-05-27)*
- **Files**: 65 (20 shell, 2 Python, 39 Markdown, 2 JSON, 2 other)
- **Test Coverage**: E2E suite passing
- **Security Issues Fixed**: 5 critical
- **Status**: Production Ready ✅

---

**Built with ❤️ by the HTE community**

**Star ⭐ this repo if you find it useful!**
