#!/usr/bin/env python3
"""
State management utility for Team Engine with file locking
"""
import json
import sys
import time
from datetime import datetime
from pathlib import Path

# Cross-platform file locking using filelock library
# This provides consistent locking behavior across Windows, Linux, and macOS
from filelock import FileLock, Timeout as FileLockTimeout

def load_state(state_file):
    """Load current state with validation"""
    if not state_file.exists():
        return {}
    
    try:
        with open(state_file, 'r') as f:
            state = json.load(f)
            # Validate basic structure
            if not isinstance(state, dict):
                raise ValueError("State must be a dictionary")
            return state
    except (json.JSONDecodeError, ValueError) as e:
        # Backup corrupted file
        backup = state_file.with_suffix('.json.corrupted')
        if state_file.exists():
            state_file.rename(backup)
        print(f"Warning: Corrupted state file backed up to {backup}", file=sys.stderr)
        return {}

def save_state(state_file, state):
    """Save state atomically with timestamp"""
    state['updated_at'] = datetime.utcnow().isoformat() + 'Z'
    
    # Write to temporary file first
    temp_file = state_file.with_suffix('.json.tmp')
    with open(temp_file, 'w') as f:
        json.dump(state, f, indent=2)
        f.flush()
        # Ensure data is written to disk
        import os
        os.fsync(f.fileno())
    
    # Atomic rename
    temp_file.replace(state_file)

def update_state(state_file, updates, lock_file):
    """Update state with new values using file lock"""
    # Ensure lock file directory exists
    lock_path = Path(lock_file)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Use FileLock context manager for cross-platform locking
    lock = FileLock(str(lock_path), timeout=10)
    try:
        with lock:
            # Load current state
            state = load_state(state_file)
            
            # Apply updates
            state.update(updates)
            
            # Save atomically
            save_state(state_file, state)
            
            return state
    except FileLockTimeout:
        raise TimeoutError(f"Could not acquire lock after 10s")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: write_state.py <state_file> <key=value> [<key=value> ...]", file=sys.stderr)
        sys.exit(1)
    
    state_file = Path(sys.argv[1])
    lock_file = state_file.parent / 'state.lock'
    updates = {}
    
    for arg in sys.argv[2:]:
        if '=' not in arg:
            print(f"Warning: Invalid argument '{arg}', expected key=value format", file=sys.stderr)
            continue
        
        key, value = arg.split('=', 1)
        
        # Validate key
        if not key.replace('_', '').isalnum():
            print(f"Error: Invalid key '{key}', must be alphanumeric with underscores", file=sys.stderr)
            sys.exit(1)
        
        # Try to parse as JSON, fallback to string
        try:
            updates[key] = json.loads(value)
        except json.JSONDecodeError:
            updates[key] = value
    
    if not updates:
        print("Error: No valid updates provided", file=sys.stderr)
        sys.exit(1)
    
    try:
        state = update_state(state_file, updates, lock_file)
        print(f"State updated: {updates}")
    except TimeoutError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error updating state: {e}", file=sys.stderr)
        sys.exit(1)
