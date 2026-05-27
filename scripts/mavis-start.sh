#!/usr/bin/env bash
# DEPRECATED: Use hmte-start.sh instead
# This is a compatibility wrapper that will be removed in a future version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/hmte-start.sh" "$@"
