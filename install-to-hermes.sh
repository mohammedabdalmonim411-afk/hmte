#!/usr/bin/env bash
# install-to-hermes.sh
# Install HMTE skills to Hermes global profile

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROFILE="${HERMES_PROFILE:-default}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SKILL_NAME="hmte"
SOURCE_DIR=".claude/skills/mavis-team-engine"
TARGET_DIR="$HERMES_HOME/profiles/$PROFILE/skills/$SKILL_NAME"

echo -e "${BLUE}=== HMTE Hermes Installation ===${NC}"
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}ERROR: Source directory not found: $SOURCE_DIR${NC}"
    echo "Please run this script from the HMTE project root."
    exit 1
fi

# Check if Hermes home exists
if [ ! -d "$HERMES_HOME" ]; then
    echo -e "${YELLOW}WARNING: Hermes home directory not found: $HERMES_HOME${NC}"
    echo "Creating Hermes directory structure..."
    mkdir -p "$HERMES_HOME/profiles/$PROFILE/skills"
fi

# Check if profile exists
if [ ! -d "$HERMES_HOME/profiles/$PROFILE" ]; then
    echo -e "${YELLOW}WARNING: Profile '$PROFILE' not found${NC}"
    echo "Creating profile directory..."
    mkdir -p "$HERMES_HOME/profiles/$PROFILE/skills"
fi

# Backup existing installation if present
if [ -d "$TARGET_DIR" ]; then
    BACKUP_DIR="$TARGET_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Existing installation found. Backing up to:${NC}"
    echo "  $BACKUP_DIR"
    mv "$TARGET_DIR" "$BACKUP_DIR"
fi

# Create target directory
echo -e "${BLUE}Creating target directory...${NC}"
mkdir -p "$TARGET_DIR"

# Copy skill files
echo -e "${BLUE}Copying skill files...${NC}"
cp -r "$SOURCE_DIR"/* "$TARGET_DIR/"

# Copy agents directory
if [ -d ".claude/agents" ]; then
    echo -e "${BLUE}Copying agent definitions...${NC}"
    mkdir -p "$TARGET_DIR/agents"
    cp -r .claude/agents/* "$TARGET_DIR/agents/"
fi

# Copy hooks directory
if [ -d ".claude/hooks" ]; then
    echo -e "${BLUE}Copying hooks...${NC}"
    mkdir -p "$TARGET_DIR/hooks"
    cp -r .claude/hooks/* "$TARGET_DIR/hooks/"
fi

# Make scripts executable
echo -e "${BLUE}Setting executable permissions...${NC}"
find "$TARGET_DIR" -type f -name "*.sh" -exec chmod +x {} \;
find "$TARGET_DIR" -type f -name "*.py" -exec chmod +x {} \;

# Verify installation
echo ""
echo -e "${BLUE}=== Verification ===${NC}"
echo ""

ERRORS=0

# Check SKILL.md exists
if [ -f "$TARGET_DIR/SKILL.md" ]; then
    echo -e "${GREEN}✓${NC} SKILL.md found"
else
    echo -e "${RED}✗${NC} SKILL.md not found"
    ERRORS=$((ERRORS + 1))
fi

# Check scripts directory
if [ -d "$TARGET_DIR/scripts" ]; then
    echo -e "${GREEN}✓${NC} scripts/ directory found"
    
    # Check key scripts
    for script in write_state.py collect_evidence.sh phase_gate.sh; do
        if [ -f "$TARGET_DIR/scripts/$script" ]; then
            echo -e "${GREEN}  ✓${NC} $script"
        else
            echo -e "${RED}  ✗${NC} $script not found"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo -e "${RED}✗${NC} scripts/ directory not found"
    ERRORS=$((ERRORS + 1))
fi

# Check agents directory
if [ -d "$TARGET_DIR/agents" ]; then
    echo -e "${GREEN}✓${NC} agents/ directory found"
    
    # Check key agents
    for agent in master-planner.md phase-executor.md verifier.md; do
        if [ -f "$TARGET_DIR/agents/$agent" ]; then
            echo -e "${GREEN}  ✓${NC} $agent"
        else
            echo -e "${RED}  ✗${NC} $agent not found"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo -e "${RED}✗${NC} agents/ directory not found"
    ERRORS=$((ERRORS + 1))
fi

# Check hooks directory
if [ -d "$TARGET_DIR/hooks" ]; then
    echo -e "${GREEN}✓${NC} hooks/ directory found"
    
    # Check key hooks
    for hook in pretool_guard.sh stop_gate.sh; do
        if [ -f "$TARGET_DIR/hooks/$hook" ]; then
            echo -e "${GREEN}  ✓${NC} $hook"
        else
            echo -e "${RED}  ✗${NC} $hook not found"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo -e "${RED}✗${NC} hooks/ directory not found"
    ERRORS=$((ERRORS + 1))
fi

# Check evidence schema
if [ -f "$TARGET_DIR/evidence-schema.json" ]; then
    echo -e "${GREEN}✓${NC} evidence-schema.json found"
else
    echo -e "${RED}✗${NC} evidence-schema.json not found"
    ERRORS=$((ERRORS + 1))
fi

# Check audit checklist
if [ -f "$TARGET_DIR/audit-checklist.md" ]; then
    echo -e "${GREEN}✓${NC} audit-checklist.md found"
else
    echo -e "${RED}✗${NC} audit-checklist.md not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Final result
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}=== Installation Successful ===${NC}"
    echo ""
    echo "HMTE has been installed to:"
    echo -e "  ${BLUE}$TARGET_DIR${NC}"
    echo ""
    echo "To use in Hermes, simply invoke:"
    echo -e "  ${YELLOW}Please use the hmte skill to implement user authentication.${NC}"
    echo ""
    echo "The skill will be automatically discovered from your profile."
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Initialize a session in your project: ./scripts/mavis-start.sh"
    echo "2. Invoke the skill in Hermes"
    echo "3. Check status: ./scripts/mavis-status.sh"
    echo ""
else
    echo -e "${RED}=== Installation Failed ===${NC}"
    echo ""
    echo -e "${RED}$ERRORS error(s) found during verification.${NC}"
    echo "Please check the output above and try again."
    echo ""
    exit 1
fi

# Show profile info
echo -e "${BLUE}Profile Information:${NC}"
echo "  Profile: $PROFILE"
echo "  Hermes Home: $HERMES_HOME"
echo "  Skills Directory: $HERMES_HOME/profiles/$PROFILE/skills/"
echo ""

# Check for other skills
SKILL_COUNT=$(find "$HERMES_HOME/profiles/$PROFILE/skills/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
echo "  Total skills in profile: $SKILL_COUNT"
echo ""

echo -e "${GREEN}Installation complete!${NC}"
