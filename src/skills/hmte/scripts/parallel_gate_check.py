#!/usr/bin/env python3
"""Parallel gate 12-item hard check for parallel_safe phases.
v1.7-rework: P0-A/B/C fixes applied."""
import json, sys, os, re, fnmatch
from collections import Counter

def main():
    phases_file = sys.argv[1]
    phase_id = sys.argv[2]
    verdict_file = sys.argv[3]
    attempt = int(sys.argv[4])

    def load_json(path, label="file"):
        try:
            with open(path) as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"FAIL:{label} not found: {path}")
            sys.exit(0)
        except json.JSONDecodeError as e:
            print(f"FAIL:{label} invalid JSON: {e}")
            sys.exit(0)

    phases_data = load_json(phases_file, "phases file")
    phases = phases_data.get("phases", [])

    # P0-A: Support both "id" and "phase_id" keys
    phase = None
    for p in phases:
        pid = p.get("phase_id") or p.get("id")
        if pid == phase_id:
            phase = p
            break

    if phase is None:
        print("SEQUENTIAL")
        return

    execution_mode = phase.get("execution_mode", "sequential")
    parallel_workers = phase.get("parallel_workers", [])

    if execution_mode == "sequential" and parallel_workers:
        print("FAIL:execution_mode=sequential but parallel_workers is non-empty")
        return

    if execution_mode == "parallel_safe" and (not parallel_workers):
        print("FAIL:execution_mode=parallel_safe but parallel_workers is missing or empty")
        return

    issues = []

    if execution_mode not in ("sequential", "parallel_safe"):
        print(f"FAIL:unknown execution_mode: '{execution_mode}'")
        return

    if execution_mode == "sequential":
        print("SEQUENTIAL")
        return

    # parallel_safe: 12-item join gate
    v = load_json(verdict_file, "verdict file")

    # Check 1: worker_id legal (P1-H: dash at start for cross-platform)
    id_re = re.compile(r'^[-A-Za-z0-9_]{1,64}$')
    worker_ids = []
    for w in parallel_workers:
        wid = w.get("worker_id", "")
        worker_ids.append(wid)
        if not id_re.match(wid):
            issues.append(f"CHECK1: illegal worker_id: '{wid}'")

    duplicate_worker_ids = sorted(
        wid for wid, count in Counter(worker_ids).items()
        if wid and count > 1
    )
    if duplicate_worker_ids:
        print(f"FAIL:CHECK1b: duplicate worker_id(s): {duplicate_worker_ids}")
        return

    expected_evidence = {}
    expected_cmd_logs = {}
    for w in parallel_workers:
        wid = w.get("worker_id", "")
        if not wid:
            continue  # CHECK1 already flagged this
        expected_evidence[wid] = f".phase_control/evidence/{phase_id}_{wid}_attempt_{attempt}.json"
        expected_cmd_logs[wid] = f".phase_control/logs/{phase_id}_{wid}_attempt_{attempt}.commands.jsonl"

    all_ev_paths = list(expected_evidence.values())
    all_cl_paths = list(expected_cmd_logs.values())

    # P0-C: Validate key fields in each worker evidence
    shard_data = {}  # wid -> parsed evidence dict
    for w in parallel_workers:
        wid = w.get("worker_id", "")
        if not wid: continue
        ev_path = expected_evidence[wid]

        if not os.path.exists(ev_path):
            issues.append(f"CHECK2: evidence not found: {ev_path}")
            continue

        try:
            with open(ev_path) as f:
                ev = json.load(f)
        except Exception as e:
            issues.append(f"CHECK2: evidence invalid JSON: {ev_path}: {e}")
            continue

        # P0-C: field validation
        ev_pid = ev.get("phase_id")
        if ev_pid != phase_id:
            issues.append(f"CHECK2b: evidence phase_id={ev_pid!r} != expected {phase_id!r} ({ev_path})")

        ev_wid = ev.get("worker_id")
        if ev_wid != wid:
            issues.append(f"CHECK2c: evidence worker_id={ev_wid!r} != expected {wid!r} ({ev_path})")

        ev_attempt = ev.get("attempt")
        if ev_attempt != attempt:
            issues.append(f"CHECK2d: evidence attempt={ev_attempt} != expected {attempt} ({ev_path})")

        ev_cf = ev.get("changed_files")
        if ev_cf is None:
            issues.append(f"CHECK2e: evidence missing changed_files ({ev_path})")
        elif not isinstance(ev_cf, list):
            issues.append(f"CHECK2f: evidence changed_files is not array ({ev_path})")

        # Check command_log_path consistency
        ev_clp = ev.get("command_log_path")
        if ev_clp is not None and ev_clp != expected_cmd_logs[wid]:
            issues.append(f"CHECK2g: evidence command_log_path={ev_clp!r} != expected {expected_cmd_logs[wid]!r}")

        shard_data[wid] = ev

    # Check 3: each expected command log exists and is non-empty
    for wid, cl_path in expected_cmd_logs.items():
        if not os.path.exists(cl_path):
            issues.append(f"CHECK3: command log not found: {cl_path}")
        elif os.path.getsize(cl_path) == 0:
            issues.append(f"CHECK3: command log is empty: {cl_path}")

    # Check 4: verdict.evidence_paths covers ALL expected evidence
    verdict_ev_paths = set(v.get("evidence_paths", []))
    missing_ev = set(all_ev_paths) - verdict_ev_paths
    if missing_ev:
        issues.append(f"CHECK4: verdict.evidence_paths missing: {sorted(missing_ev)}")

    # Check 5: verdict.command_log_paths covers ALL expected command logs
    verdict_cl_paths = set(v.get("command_log_paths", []))
    missing_cl = set(all_cl_paths) - verdict_cl_paths
    if missing_cl:
        issues.append(f"CHECK5: verdict.command_log_paths missing: {sorted(missing_cl)}")

    # Check 6: join_verification present
    jv = v.get("join_verification")
    if not jv or not isinstance(jv, dict):
        issues.append("CHECK6: join_verification missing or not an object")
    else:
        # Check 7: all_worker_evidence_checked
        if jv.get("all_worker_evidence_checked") is not True:
            issues.append("CHECK7: all_worker_evidence_checked is not true")

        # Check 8: all_command_logs_checked
        if jv.get("all_command_logs_checked") is not True:
            issues.append("CHECK8: all_command_logs_checked is not true")

        # Check 9: missing_shards empty
        ms = jv.get("missing_shards", None)
        if ms is None:
            issues.append("CHECK9: missing_shards field missing")
        elif ms != []:
            issues.append(f"CHECK9: missing_shards is not empty: {ms}")

    # P0-B: Check 10 — each worker's changed_files must not hit own forbidden_paths
    for w in parallel_workers:
        wid = w.get("worker_id", "")
        if not wid: continue
        forbidden = w.get("forbidden_paths", [])
        ev = shard_data.get(wid)
        if ev is None:
            continue
        changed = ev.get("changed_files", [])
        if not isinstance(changed, list):
            continue
        for fpath in changed:
            for fp in forbidden:
                # Normalize: support dir prefix, trailing slash, and glob
                fp_clean = fp.rstrip("/")
                if fnmatch.fnmatch(fpath, fp) or fnmatch.fnmatch(fpath, fp + "/*") or fnmatch.fnmatch(fpath, fp + "/**"):
                    issues.append(f"CHECK10: {wid} changed '{fpath}' hits own forbidden_path '{fp}'")
                    break
                # Directory prefix: src/api protects src/api/foo.py but NOT src/api_v2/foo.py
                if fpath.startswith(fp_clean + "/"):
                    issues.append(f"CHECK10: {wid} changed '{fpath}' hits own forbidden_path '{fp}'")
                    break

    # Check 11: changed_files overlap between workers
    all_wids = list(shard_data.keys())
    for i in range(len(all_wids)):
        for j in range(i + 1, len(all_wids)):
            cf_i = set(shard_data[all_wids[i]].get("changed_files", []) or [])
            cf_j = set(shard_data[all_wids[j]].get("changed_files", []) or [])
            overlap = cf_i & cf_j
            if overlap:
                issues.append(f"CHECK11: changed_files overlap between {all_wids[i]} and {all_wids[j]}: {sorted(overlap)}")

    # Check 12: no BLOCKED/PARTIAL/FAIL evidence with PASS verdict
    verdict_status = v.get("status", "").upper()
    if verdict_status == "PASS":
        for w in parallel_workers:
            wid = w.get("worker_id", "")
            if not wid: continue
            ev = shard_data.get(wid)
            if ev is None:
                continue
            ev_status = ev.get("status", "").upper()
            if ev_status in ("BLOCKED", "PARTIAL", "FAIL"):
                issues.append(f"CHECK12: {wid} evidence.status={ev_status} but verdict is PASS")

    if issues:
        print("FAIL:" + "; ".join(issues))
    else:
        print("PASS")

if __name__ == "__main__":
    main()
