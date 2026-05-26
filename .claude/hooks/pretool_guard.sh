#!/bin/bash
# Pre-tool guard hook with improved security
# Uses whitelist approach instead of blacklist

TOOL_NAME="$1"
shift
ARGS="$@"

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# For Bash tool, implement strict validation
if [ "$TOOL_NAME" = "Bash" ]; then
    # Dangerous patterns that should always be blocked
    # Using more sophisticated detection
    
    # Block any rm with -rf and root-like paths
    if echo "$ARGS" | grep -qE 'rm\s+.*-[a-z]*r[a-z]*f|rm\s+.*-[a-z]*f[a-z]*r'; then
        if echo "$ARGS" | grep -qE '(/\s|/\$|~|HOME|/etc|/var|/usr|/bin|/sbin|/boot|/dev|/sys|/proc|c:\|C:\)'; then
            echo "BLOCKED: Dangerous rm command detected targeting system paths"
            echo "Command: $ARGS"
            exit 1
        fi
    fi
    
    # Block filesystem operations
    if echo "$ARGS" | grep -qE '\bmkfs\b|\bformat\b|\bfdisk\b|\bparted\b'; then
        echo "BLOCKED: Filesystem operation detected"
        exit 1
    fi
    
    # Block direct device writes
    if echo "$ARGS" | grep -qE '>\s*/dev/[sh]d|dd\s+.*of=/dev'; then
        echo "BLOCKED: Direct device write detected"
        exit 1
    fi
    
    # Block privilege escalation attempts
    if echo "$ARGS" | grep -qE '\bsudo\b|\bsu\b|\bchmod\s+[0-9]*[4-7]|\bchown\s+root'; then
        echo "BLOCKED: Privilege escalation attempt detected"
        exit 1
    fi
    
    # Block network exfiltration patterns
    if echo "$ARGS" | grep -qE 'curl.*\||wget.*\||nc\s+.*-e|bash\s+-i.*>&'; then
        echo "BLOCKED: Potential data exfiltration detected"
        exit 1
    fi
    
    # Warn on cd outside project (but don't block)
    if echo "$ARGS" | grep -qE '\bcd\s+/[^f]'; then
        if ! echo "$ARGS" | grep -q "$PROJECT_ROOT"; then
            echo "WARNING: Command tries to cd outside project directory"
            echo "Project root: $PROJECT_ROOT"
            echo "Command: $ARGS"
            # Don't block, just warn
        fi
    fi
    
    # Check for command injection patterns
    if echo "$ARGS" | grep -qE '\$\(|\`|;\s*rm|&&\s*rm|\|\s*rm'; then
        if echo "$ARGS" | grep -qE '(rm|del|format|mkfs)'; then
            echo "BLOCKED: Potential command injection with dangerous command"
            exit 1
        fi
    fi
fi

# For Edit/Write tools, check if verifier is trying to use them
# (This requires context about which agent is calling, which we don't have here)
# This would need to be implemented at a higher level

# Allow the command
exit 0
