#!/usr/bin/env python3
"""
State management utility for Team Engine with file locking
"""
import json
import sys
import fcntl
import time
from datetime import datetime
from pathlib import Path

def acquire_lock(lock_file, timeout=10):
    """Acquire exclusive lock with timeout"""
    lock_path = Path(lock_file)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    
    start_time = time.time()
    while True:
        try:
            fd = open(lock_path, 'w')
            fcntl.flock(fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except (IOError, OSError):
            if time.time() - start_time > timeout:
                raise TimeoutError(f"Could not acquire lock after {timeout}s")
            time.sleep(0.1)

def release_lock(fd):
    """Release lock and close file"""
    if fd:
        fcntl.flock(fd.fileno(), fcntl.LOCK_UN)
        fd.close()

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
    lock_fd = None
    try:
        # Acquire lock
        lock_fd = acquire_lock(lock_file)
        
        # Load current state
        state = load_state(state_file)
        
        # Apply updates
        state.update(updates)
        
        # Save atomically
        save_state(state_file, state)
        
        return state
    finally:
        # Always release lock
        if lock_fd:
            release_lock(lock_fd)

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
