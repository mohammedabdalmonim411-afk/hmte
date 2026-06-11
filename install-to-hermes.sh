#!/bin/bash
# install-to-hermes.sh — Install TriAgentFlow / TAF skill into Hermes
#
# Usage:
#   bash install-to-hermes.sh [--all|--profile NAME|--global|--verify-only] [--force]
#
# --all          Install to BOTH profile AND global + install deps + verify (default)
# --profile NAME Install to specific profile only
# --global       Install to global skills directory only
# --verify-only  Only verify, don't install (checks both profile + global)
# --force        Overwrite existing files without prompting
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

MODE="all"
PROFILE="default"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
FORCE=false
VERIFY_ONLY=false

# ─── Parse args ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)         MODE="all"; shift ;;
        --profile)     MODE="profile"; PROFILE="${2:?--profile requires a name}"; shift 2 ;;
        --global)      MODE="global"; shift ;;
        --verify-only) VERIFY_ONLY=true; shift ;;
        --force)       FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--all|--profile NAME|--global|--verify-only] [--force]"
            echo ""
            echo "  --all          Install to BOTH profile AND global + deps + verify (default)"
            echo "  --profile NAME Install to specific Hermes profile only"
            echo "  --global       Install to global skills directory only"
            echo "  --verify-only  Only verify installation (checks both profile + global), don't copy"
            echo "  --force        Overwrite without prompting"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ─── Determine install targets ─────────────────────────────────
if [ "$MODE" = "all" ]; then
    # --all: install to BOTH profile and global
    TARGETS=(
        "profile:$HERMES_HOME/profiles/$PROFILE/skills/hmte"
        "global:$HERMES_HOME/skills/hmte"
    )
elif [ "$MODE" = "profile" ]; then
    TARGETS=("profile:$HERMES_HOME/profiles/$PROFILE/skills/hmte")
elif [ "$MODE" = "global" ]; then
    TARGETS=("global:$HERMES_HOME/skills/hmte")
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  TriAgentFlow / TAF — Install to Hermes     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Mode:       $MODE"
echo "  Profile:    $PROFILE"
echo "  Targets:"
for t in "${TARGETS[@]}"; do
    echo "    → ${t%%:*}: ${t#*:}"
done
echo "  Project:    $PROJECT_ROOT"
echo ""

# ─── Step 1: Install Python dependencies ──────────────────────
if [ "$VERIFY_ONLY" = false ]; then
    echo "── Step 1: Install Python dependencies ──"
    REQ_FILE="$PROJECT_ROOT/requirements.txt"
    if [ -f "$REQ_FILE" ]; then
        DEPS_INSTALLED=false
        if command -v uv >/dev/null 2>&1; then
            echo "  Using uv..."
            uv pip install -r "$REQ_FILE" 2>/dev/null && DEPS_INSTALLED=true
        fi
        if [ "$DEPS_INSTALLED" = false ] && python3 -m pip --version >/dev/null 2>&1; then
            echo "  Using python3 -m pip..."
            python3 -m pip install -r "$REQ_FILE" --user -q 2>/dev/null && DEPS_INSTALLED=true
        fi
        if [ "$DEPS_INSTALLED" = false ] && command -v pip >/dev/null 2>&1; then
            echo "  Using pip..."
            pip install -r "$REQ_FILE" --user -q 2>/dev/null && DEPS_INSTALLED=true
        fi
        if [ "$DEPS_INSTALLED" = true ]; then
            echo "  ✅ Dependencies installed"
        else
            echo "  ⚠️  Could not auto-install dependencies (non-fatal, may already be installed)"
        fi
    else
        echo "  ⚠️  No requirements.txt found"
    fi
    echo ""
fi

# ─── Step 2: Copy skill files to each target ──────────────────
if [ "$VERIFY_ONLY" = false ]; then
    echo "── Step 2: Copy skill files ──"

    for target_entry in "${TARGETS[@]}"; do
        target_label="${target_entry%%:*}"
        TARGET_DIR="${target_entry#*:}"

        echo "  Installing to [$target_label]: $TARGET_DIR"

        # Create target directories
        mkdir -p "$TARGET_DIR"
        mkdir -p "$TARGET_DIR/scripts"
        mkdir -p "$TARGET_DIR/hooks"
        mkdir -p "$TARGET_DIR/agents"

        COPIED=0
        SKIPPED=0

        # Copy skill definition
        for f in SKILL.md phase-template.md audit-checklist.md final-audit-template.md; do
            src="$PROJECT_ROOT/src/skills/hmte/$f"
            if [ -f "$src" ]; then
                cp "$src" "$TARGET_DIR/$f"
                COPIED=$((COPIED + 1))
            fi
        done

        # Copy schemas
        for f in evidence-schema.json verdict-schema.json delegation-receipt-schema.json; do
            src="$PROJECT_ROOT/src/skills/hmte/$f"
            if [ -f "$src" ]; then
                cp "$src" "$TARGET_DIR/$f"
                COPIED=$((COPIED + 1))
            fi
        done

        # Copy scripts
        for f in orchestrator.py hmte-audit-flow.py parallel_gate_check.py phase_gate.sh write_state.py collect_evidence.sh; do
            src="$PROJECT_ROOT/src/skills/hmte/scripts/$f"
            if [ -f "$src" ]; then
                cp "$src" "$TARGET_DIR/scripts/$f"
                COPIED=$((COPIED + 1))
            fi
        done

        # Copy hooks
        for f in pretool_guard.sh stop_gate.sh task_naming.sh; do
            src="$PROJECT_ROOT/src/skills/hmte/hooks/$f"
            if [ -f "$src" ]; then
                cp "$src" "$TARGET_DIR/hooks/$f"
                COPIED=$((COPIED + 1))
            fi
        done

        # Copy agents
        for f in master-planner.md phase-executor.md verifier.md release-auditor.md; do
            src="$PROJECT_ROOT/src/agents/$f"
            if [ -f "$src" ]; then
                cp "$src" "$TARGET_DIR/agents/$f"
                COPIED=$((COPIED + 1))
            fi
        done

        echo "  ✅ [$target_label] Copied $COPIED files"
    done
    echo ""
fi

# ─── Step 3: Verify installation (all targets) ─────────────────
echo "── Step 3: Verify installation ──"

OVERALL_ERRORS=0

for target_entry in "${TARGETS[@]}"; do
    target_label="${target_entry%%:*}"
    TARGET_DIR="${target_entry#*:}"

    echo ""
    echo "  Verifying [$target_label]: $TARGET_DIR"
    ERRORS=0

    # Check target directory exists
    if [ ! -d "$TARGET_DIR" ]; then
        echo "    ❌ Target directory not found"
        ERRORS=$((ERRORS + 1))
    else
        echo "    ✅ Target directory exists"
    fi

    # Check critical files
    CRITICAL_FILES=(
        "SKILL.md"
        "scripts/hmte-audit-flow.py"
        "scripts/parallel_gate_check.py"
        "scripts/phase_gate.sh"
        "hooks/pretool_guard.sh"
        "agents/verifier.md"
    )

    for f in "${CRITICAL_FILES[@]}"; do
        if [ -f "$TARGET_DIR/$f" ]; then
            echo "    ✅ $f"
        else
            echo "    ❌ MISSING: $f"
            ERRORS=$((ERRORS + 1))
        fi
    done

    # Syntax check Python files
    for pyfile in "$TARGET_DIR"/scripts/*.py; do
        if [ -f "$pyfile" ]; then
            if python3 -m py_compile "$pyfile" 2>/dev/null; then
                echo "    ✅ $(basename "$pyfile") syntax OK"
            else
                echo "    ❌ $(basename "$pyfile") syntax error"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done

    # Syntax check Bash files
    for shfile in "$TARGET_DIR"/scripts/*.sh "$TARGET_DIR"/hooks/*.sh; do
        if [ -f "$shfile" ]; then
            if bash -n "$shfile" 2>/dev/null; then
                echo "    ✅ $(basename "$shfile") syntax OK"
            else
                echo "    ❌ $(basename "$shfile") syntax error"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done

    if [ "$ERRORS" -gt 0 ]; then
        echo "    ❌ [$target_label] Verification FAILED ($ERRORS errors)"
    else
        echo "    ✅ [$target_label] Verification PASSED"
    fi

    OVERALL_ERRORS=$((OVERALL_ERRORS + ERRORS))
done

# ─── Check Python dependency ────────────────────────────────────
echo ""
if python3 -c "import filelock" 2>/dev/null; then
    echo "  ✅ Python dependency (filelock) available"
else
    echo "  ❌ Python dependency (filelock) NOT installed"
    echo "     Fix: pip install filelock"
    OVERALL_ERRORS=$((OVERALL_ERRORS + 1))
fi

# ─── CLI visibility check ───────────────────────────────────────
echo ""
if [ -d "$HERMES_HOME/skills/hmte" ]; then
    echo "  ✅ Global skill visible at: $HERMES_HOME/skills/hmte"
else
    echo "  ⚠️  Global skill NOT installed (Hermes CLI may not see skill)"
    if [ "$MODE" = "all" ]; then
        OVERALL_ERRORS=$((OVERALL_ERRORS + 1))
    fi
fi

echo ""

# ─── Result ────────────────────────────────────────────────────
if [ "$OVERALL_ERRORS" -gt 0 ]; then
    echo "╔══════════════════════════════════════════════╗"
    echo "  ⚠️  Installation completed with $OVERALL_ERRORS error(s)"
    echo "╚══════════════════════════════════════════════╝"
    exit 1
else
    echo "╔══════════════════════════════════════════════╗"
    echo "  ✅ TriAgentFlow / TAF installed successfully! (all targets)"
    echo ""
    echo "  Targets verified:"
    for t in "${TARGETS[@]}"; do
        echo "    ✅ ${t%%:*}: ${t#*:}"
    done
    echo ""
    echo "  Next steps:"
    echo "    1. cd /path/to/your/project"
    echo "    2. mkdir -p scripts && cp -R $(pwd)/scripts/. ./scripts/ && test -f scripts/hmte-kickoff.sh && test ! -d scripts/scripts"
    echo "    3. bash scripts/hmte-kickoff.sh \"your task\""
    echo "    4. bash scripts/hmte-goal-lock.sh"
    echo "╚══════════════════════════════════════════════╝"
    exit 0
fi
