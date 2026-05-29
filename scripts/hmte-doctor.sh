#!/usr/bin/env bash
# hmte-doctor.sh - 检查环境依赖和配置

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

FAIL_COUNT=0
WARN_COUNT=0

check_cmd() {
    local cmd="$1"
    local required="${2:-true}"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        success "$cmd found: $(command -v "$cmd")"
        return 0
    else
        if [ "$required" = "true" ]; then
            error "$cmd missing (required)"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            warn "$cmd missing (optional)"
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
        return 1
    fi
}

check_python_module() {
    local module="$1"
    local required="${2:-true}"
    
    if python3 -c "import $module" 2>/dev/null; then
        success "Python module '$module' found"
        return 0
    else
        if [ "$required" = "true" ]; then
            error "Python module '$module' missing (required)"
            echo "       Install: pip install $module"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            warn "Python module '$module' missing (optional)"
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
        return 1
    fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 HTE Environment Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. 检查必需命令
info "Checking required commands..."
check_cmd bash true
check_cmd git true
check_cmd python3 true

# 2. 检查可选命令
echo ""
info "Checking optional commands..."
check_cmd jq false

if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found: status output will be degraded"
    echo "       Install: brew install jq (macOS) or apt install jq (Linux)"
fi



# 3. 检查Python模块
echo ""
info "Checking Python modules..."
check_python_module json true
check_python_module pathlib true
check_python_module datetime true

# filelock是可选的（我们会用标准库替代）
if ! check_python_module filelock false; then
    info "filelock not found, will use standard library fcntl/msvcrt"
fi

# 4. 检查Git配置
echo ""
info "Checking Git configuration..."
if git config user.name >/dev/null 2>&1; then
    success "Git user.name: $(git config user.name)"
else
    warn "Git user.name not set"
    echo "       Set: git config --global user.name 'Your Name'"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

if git config user.email >/dev/null 2>&1; then
    success "Git user.email: $(git config user.email)"
else
    warn "Git user.email not set"
    echo "       Set: git config --global user.email 'you@example.com'"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# 5. 检查项目结构
echo ""
info "Checking project structure..."

if [ -d .phase_control ]; then
    success ".phase_control directory exists"
    
    # 检查子目录
    for dir in evidence verdicts logs pids traces; do
        if [ -d ".phase_control/$dir" ]; then
            success ".phase_control/$dir exists"
        else
            warn ".phase_control/$dir missing"
            echo "       Run: hmte init"
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
    done
    
    # 检查state.json
    if [ -f .phase_control/state.json ]; then
        success ".phase_control/state.json exists"
        
        # 验证JSON格式
        if python3 -c "import json; json.load(open('.phase_control/state.json'))" 2>/dev/null; then
            success "state.json is valid JSON"
        else
            error "state.json is corrupted"
            echo "       Backup: mv .phase_control/state.json .phase_control/state.json.corrupted"
            echo "       Reinit: hmte init"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        warn ".phase_control/state.json missing"
        echo "       Run: hmte init"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
else
    warn ".phase_control directory not found"
    echo "       Run: hmte init"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# 6. 检查HTE skill安装
echo ""
info "Checking HTE skill installation..."

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_PROFILE="${HERMES_PROFILE:-default}"
SKILL_DIR="$HERMES_HOME/profiles/$HERMES_PROFILE/skills/hmte"

if [ -d "$SKILL_DIR" ]; then
    success "HTE skill found: $SKILL_DIR"
    
    # 检查关键文件
    if [ -f "$SKILL_DIR/SKILL.md" ]; then
        success "SKILL.md found"
    else
        error "SKILL.md missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    if [ -d "$SKILL_DIR/scripts" ]; then
        success "scripts/ directory found"
    else
        error "scripts/ directory missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    error "HTE skill not installed"
    echo "       Install: cd /path/to/hmte && ./install-to-hermes.sh"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# 7. 检查权限
echo ""
info "Checking permissions..."

if [ -w . ]; then
    success "Current directory is writable"
else
    error "Current directory is not writable"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if [ -d .phase_control ] && [ -w .phase_control ]; then
    success ".phase_control is writable"
elif [ -d .phase_control ]; then
    error ".phase_control is not writable"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# 8. 总结
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAIL_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "HTE environment is ready to use."
    exit 0
elif [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${YELLOW}⚠ ${WARN_COUNT} warning(s) found${NC}"
    echo ""
    echo "HTE can run but some features may be degraded."
    echo "Review warnings above and install optional dependencies if needed."
    exit 0
else
    echo -e "${RED}✗ ${FAIL_COUNT} error(s) found${NC}"
    if [ $WARN_COUNT -gt 0 ]; then
        echo -e "${YELLOW}⚠ ${WARN_COUNT} warning(s) found${NC}"
    fi
    echo ""
    echo "HTE cannot run until errors are fixed."
    echo "Review errors above and follow the suggested fixes."
    exit 1
fi
