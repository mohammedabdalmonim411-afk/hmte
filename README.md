# Mavis Team Engine

> A Claude-native multi-agent development system implementing the Leader/Worker/Verifier pattern for rigorous, phase-based software development.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-green.svg)]()

## 🎯 What is Mavis Team Engine?

Mavis Team Engine is a **production-ready framework** that brings structured, multi-agent collaboration to Claude Code. Inspired by MiniMax's Mavis architecture, it enforces a rigorous "plan → execute → verify → release" cycle with:

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

Mavis Team Engine solves these with:
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

- **Claude Code** (CLI, Desktop, or Web)
- **Python 3.8+**
- **Git**
- **Bash** (Unix-like shell)

### Installation

1. **Clone or copy this repository to your project:**

```bash
# Option 1: Clone as a submodule
git submodule add https://github.com/yourusername/mavis-team-engine .mavis

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

2. **Invoke the skill in Claude Code:**
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

### Example: Implementing User Authentication

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

```
.
├── .claude/
│   ├── skills/mavis-team-engine/
│   │   ├── SKILL.md                    # Main skill definition
│   │   ├── phase-template.md           # Phase definition template
│   │   ├── evidence-schema.json        # Evidence bundle JSON schema
│   │   ├── audit-checklist.md          # Verifier checklist
│   │   └── scripts/
│   │       ├── write_state.py          # State management (with file locking)
│   │       ├── collect_evidence.sh     # Evidence collection helper
│   │       └── phase_gate.sh           # Phase gate checker
│   ├── agents/
│   │   ├── master-planner.md           # Leader agent definition
│   │   ├── phase-executor.md           # Worker agent definition
│   │   └── verifier.md                 # Verifier agent definition
│   └── hooks/
│       ├── stop_gate.sh                # Prevents stopping with incomplete work
│       ├── pretool_guard.sh            # Blocks dangerous commands
│       └── task_naming.sh              # Enforces task naming conventions
├── .phase_control/
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
├── CLAUDE.md                           # Project rules
├── README.md                           # This file
├── LICENSE                             # MIT License
└── .gitignore                          # Git ignore rules
```

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

To change models, edit `.claude/agents/<agent-name>.md`:

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
3. Invoke skill in Claude Code
4. Check status: `./scripts/mavis-status.sh`
5. Verify evidence in `.phase_control/evidence/`
6. Verify verdicts in `.phase_control/verdicts/`
7. Stop session: `./scripts/mavis-stop.sh`

## 📊 Performance

### Token Costs

Multi-agent workflows consume approximately **7x** normal conversation tokens:
- Leader planning: ~2x
- Worker execution: ~3x
- Verifier audit: ~2x

**Optimization tips:**
- Use Sonnet for Worker (cheaper, still capable)
- Keep phases focused and small
- Provide clear acceptance criteria
- Use evidence bundles instead of full context

### Execution Time

Typical phase execution:
- Simple phase (add function): 2-5 minutes
- Medium phase (implement API): 5-15 minutes
- Complex phase (full feature): 15-30 minutes

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

# If stuck, manually update state
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
| **Mavis Team Engine** | Enforced gates, audit trail, isolation | Higher token cost, slower | Production code, critical features |
| **External Orchestrator** | Maximum control | Complex setup, maintenance | Platform-level automation |

## 📚 Documentation

- **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)** - Detailed design document
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Build summary
- **[FINAL_REPORT.md](FINAL_REPORT.md)** - Project completion report
- **[SECURITY_FIXES.md](SECURITY_FIXES.md)** - Security improvements
- **[VERIFICATION_REPORT.md](VERIFICATION_REPORT.md)** - Test results
- **[CLAUDE.md](CLAUDE.md)** - Project rules for Claude Code

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
git clone https://github.com/yourusername/mavis-team-engine.git
cd mavis-team-engine

# Run tests
./scripts/mavis-e2e.sh

# Make changes
# ...

# Test changes
./scripts/mavis-start.sh
# Use in Claude Code
./scripts/mavis-stop.sh
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **MiniMax** - Inspiration from Mavis architecture
- **Anthropic** - Claude Code platform and MCP protocol
- **TeamBench** - Research on multi-agent system failures
- **Community** - Feedback and contributions

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/mavis-team-engine/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/mavis-team-engine/discussions)
- **Documentation**: [Project Wiki](https://github.com/yourusername/mavis-team-engine/wiki)

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

- **Lines of Code**: ~4,500+
- **Files**: 26
- **Test Coverage**: E2E suite passing
- **Security Issues Fixed**: 5 critical
- **Development Time**: ~2 hours
- **Status**: Production Ready ✅

---

**Built with ❤️ by the Mavis Team Engine community**

**Star ⭐ this repo if you find it useful!**
