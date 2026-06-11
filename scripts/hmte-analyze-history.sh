#!/usr/bin/env bash
# hmte-analyze-history.sh - Historical data analysis script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
LEDGER=""
OUTPUT=""
METRIC="all"
PROJECT=""
VERBOSE=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Analyze TAF run ledger for historical trends and metrics.

OPTIONS:
    --ledger PATH           Run ledger JSONL file
    --output PATH           Output JSON file (optional)
    --metric METRIC         Metric to analyze: all (default) | phase_success_rate | timeout_rate | rework_rate | selector_accuracy
    --project NAME          Filter by project name
    --verbose               Verbose output
    -h, --help              Show this help

EXAMPLES:
    # Generate full report
    $(basename "$0") --ledger .phase_control/run_ledger.jsonl --output history_analysis.json

    # Query specific metric
    $(basename "$0") --ledger .phase_control/run_ledger.jsonl --metric timeout_rate

EOF
    exit 0
}

log() {
    if [ "$VERBOSE" = true ]; then
        echo "[hmte-analyze-history] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ledger)
            LEDGER="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --metric)
            METRIC="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
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
[ -z "$LEDGER" ] && error "--ledger required"
[ ! -f "$LEDGER" ] && error "Ledger not found: $LEDGER"

log "Ledger: $LEDGER"
log "Metric: $METRIC"
[ -n "$PROJECT" ] && log "Project filter: $PROJECT"

# Check if ledger is empty
if [ ! -s "$LEDGER" ]; then
    log "Empty ledger, generating empty report"
    if [ -n "$OUTPUT" ]; then
        echo '{"status": "empty_ledger", "metrics": {}}' > "$OUTPUT"
    fi
    echo "Empty ledger, no data to analyze"
    exit 0
fi

# Analyze metrics
log "Analyzing metrics..."

python3 << 'PYEOF' "$LEDGER" "$METRIC" "$PROJECT" "$OUTPUT"
import json
import sys
from collections import defaultdict

ledger_path = sys.argv[1]
metric = sys.argv[2]
project_filter = sys.argv[3]
output_path = sys.argv[4]

# Parse ledger
records = []
with open(ledger_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
            # Filter by project if specified
            if project_filter and record.get('project') != project_filter:
                continue
            records.append(record)
        except json.JSONDecodeError:
            print(f"Warning: Skipping invalid JSON line", file=sys.stderr)
            continue

if not records:
    print("No records found")
    if output_path:
        with open(output_path, 'w') as f:
            json.dump({"status": "no_records", "metrics": {}}, f, indent=2)
    sys.exit(0)

# Compute metrics
metrics = {}

# 1. Phase success rate
if metric in ['all', 'phase_success_rate']:
    phase_stats = defaultdict(lambda: {'total': 0, 'pass': 0, 'fail': 0})
    for r in records:
        phase_type = r.get('phase_type', 'unknown')
        phase_stats[phase_type]['total'] += 1
        if r.get('status') == 'PASS':
            phase_stats[phase_type]['pass'] += 1
        else:
            phase_stats[phase_type]['fail'] += 1
    
    phase_success_rate = {}
    for phase_type, stats in phase_stats.items():
        phase_success_rate[phase_type] = {
            'total': stats['total'],
            'pass': stats['pass'],
            'fail': stats['fail'],
            'success_rate': stats['pass'] / stats['total'] if stats['total'] > 0 else 0
        }
    
    metrics['phase_success_rate'] = phase_success_rate

# 2. Timeout rate
if metric in ['all', 'timeout_rate']:
    total = len(records)
    timeout_count = sum(1 for r in records if r.get('timeout', False))
    
    by_intensity = defaultdict(lambda: {'total': 0, 'timeout': 0})
    by_phase_type = defaultdict(lambda: {'total': 0, 'timeout': 0})
    
    for r in records:
        intensity = r.get('intensity', 'unknown')
        phase_type = r.get('phase_type', 'unknown')
        
        by_intensity[intensity]['total'] += 1
        by_phase_type[phase_type]['total'] += 1
        
        if r.get('timeout', False):
            by_intensity[intensity]['timeout'] += 1
            by_phase_type[phase_type]['timeout'] += 1
    
    metrics['timeout_rate'] = {
        'overall': timeout_count / total if total > 0 else 0,
        'by_intensity': {k: v['timeout'] / v['total'] if v['total'] > 0 else 0 
                        for k, v in by_intensity.items()},
        'by_phase_type': {k: v['timeout'] / v['total'] if v['total'] > 0 else 0 
                         for k, v in by_phase_type.items()}
    }

# 3. Rework rate
if metric in ['all', 'rework_rate']:
    total = len(records)
    rework_count = sum(1 for r in records if r.get('rework_count', 0) > 0)
    avg_rework = sum(r.get('rework_count', 0) for r in records) / total if total > 0 else 0
    
    by_intensity = defaultdict(lambda: {'total': 0, 'rework': 0})
    for r in records:
        intensity = r.get('intensity', 'unknown')
        by_intensity[intensity]['total'] += 1
        if r.get('rework_count', 0) > 0:
            by_intensity[intensity]['rework'] += 1
    
    metrics['rework_rate'] = {
        'overall': rework_count / total if total > 0 else 0,
        'by_intensity': {k: v['rework'] / v['total'] if v['total'] > 0 else 0 
                        for k, v in by_intensity.items()},
        'avg_rework_count': avg_rework
    }

# Output
if output_path:
    with open(output_path, 'w') as f:
        json.dump(metrics, f, indent=2)
    print(f"Analysis saved to: {output_path}")
else:
    print(json.dumps(metrics, indent=2))

print(f"\nAnalyzed {len(records)} records")
PYEOF

log "Analysis complete"
exit 0
