#!/usr/bin/env bash
# hmte-evidence-replay.sh - Evidence replay script (MVP: dry-run / read-only / hash-comparison)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
EVIDENCE=""
MODE="dry-run"
VERBOSE=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Replay evidence bundle (v2.0 MVP: dry-run / read-only / hash-comparison only).

OPTIONS:
    --evidence PATH         Evidence JSON file
    --mode MODE             Replay mode: dry-run (default) | read-only | hash-comparison
    --verbose               Verbose output
    -h, --help              Show this help

MODES:
    dry-run                 Parse evidence, no execution (default)
    read-only               Execute read-only commands only
    hash-comparison         Compare file hashes

EXAMPLES:
    # Dry-run verification
    $(basename "$0") --evidence .phase_control/evidence/phase_1_attempt_1.json

    # Hash comparison
    $(basename "$0") --evidence .phase_control/evidence/phase_1_attempt_1.json --mode hash-comparison

EOF
    exit 0
}

log() {
    if [ "$VERBOSE" = true ]; then
        echo "[hmte-evidence-replay] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --evidence)
            EVIDENCE="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate
[ -z "$EVIDENCE" ] && error "--evidence required"
[ ! -f "$EVIDENCE" ] && error "Evidence not found: $EVIDENCE"

case "$MODE" in
    dry-run|read-only|hash-comparison)
        ;;
    *)
        error "Invalid mode: $MODE (must be dry-run, read-only, or hash-comparison)"
        ;;
esac

log "Mode: $MODE"
log "Evidence: $EVIDENCE"

# Parse evidence JSON
log "Parsing evidence..."
if ! python3 -m json.tool "$EVIDENCE" > /dev/null 2>&1; then
    error "Invalid JSON: $EVIDENCE"
fi

# Extract fields
PHASE_ID=$(python3 -c "import json; print(json.load(open('$EVIDENCE')).get('phase_id', 'unknown'))" 2>/dev/null || echo "unknown")
PLAN_REF=$(python3 -c "import json; pr=json.load(open('$EVIDENCE')).get('plan_ref', {}); print('present' if pr else 'missing')" 2>/dev/null || echo "missing")
CHANGED_FILES=$(python3 -c "import json; cf=json.load(open('$EVIDENCE')).get('changed_files', []); print(len(cf))" 2>/dev/null || echo "0")

log "Phase ID: $PHASE_ID"
log "Plan ref: $PLAN_REF"
log "Changed files: $CHANGED_FILES"

# Mode-specific checks
case "$MODE" in
    dry-run)
        echo "=== Dry-Run Mode ==="
        echo "Evidence structure: VALID"
        echo "Plan ref: $PLAN_REF"
        echo "Changed files count: $CHANGED_FILES"
        
        # Check plan_ref
        if [ "$PLAN_REF" = "missing" ]; then
            error "Plan ref missing in evidence"
        fi
        
        echo "Status: PASS"
        ;;
        
    read-only)
        echo "=== Read-Only Mode ==="
        # Check file existence
        FILES=$(python3 -c "import json; print(' '.join(json.load(open('$EVIDENCE')).get('changed_files', [])))" 2>/dev/null || echo "")
        
        if [ -z "$FILES" ]; then
            echo "No files to check"
        else
            for file in $FILES; do
                if [ -f "$file" ]; then
                    echo "✓ $file: EXISTS"
                else
                    echo "✗ $file: MISSING"
                fi
            done
        fi
        
        echo "Status: PASS"
        ;;
        
    hash-comparison)
        echo "=== Hash Comparison Mode ==="
        # Extract file hashes
        HAS_HASHES=$(python3 -c "import json; fh=json.load(open('$EVIDENCE')).get('file_hashes', {}); print('yes' if fh else 'no')" 2>/dev/null || echo "no")
        
        if [ "$HAS_HASHES" = "no" ]; then
            echo "No file hashes in evidence"
            echo "Status: SKIP"
            exit 0
        fi
        
        # Compare hashes
        MATCHED=0
        MISMATCHED=0
        
        python3 << 'PYEOF' "$EVIDENCE"
import json
import sys
import hashlib
import os

evidence_path = sys.argv[1]
with open(evidence_path) as f:
    evidence = json.load(f)

file_hashes = evidence.get('file_hashes', {})
matched = 0
mismatched = 0

for file_path, expected_hash in file_hashes.items():
    if not os.path.exists(file_path):
        print(f"✗ {file_path}: MISSING")
        mismatched += 1
        continue
    
    with open(file_path, 'rb') as f:
        actual_hash = "sha256:" + hashlib.sha256(f.read()).hexdigest()
    
    if actual_hash == expected_hash:
        print(f"✓ {file_path}: MATCH")
        matched += 1
    else:
        print(f"✗ {file_path}: MISMATCH")
        print(f"  Expected: {expected_hash}")
        print(f"  Actual: {actual_hash}")
        mismatched += 1

print(f"\nTotal: {len(file_hashes)} files, {matched} matched, {mismatched} mismatched")

if mismatched > 0:
    sys.exit(1)
PYEOF
        
        if [ $? -eq 0 ]; then
            echo "Status: PASS"
        else
            echo "Status: FAIL"
            exit 1
        fi
        ;;
esac

log "Evidence replay complete"
exit 0
