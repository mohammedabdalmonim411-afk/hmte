#!/usr/bin/env python3
"""
HTE Anti-Fake Audit Flow
========================
Audits a phase's complete execution chain:
  delegation intent receipt → command log → evidence → verdict

Exit 0 = PASS, Exit 1 = FAIL.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional, Tuple

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Check:
    name: str
    status: str  # "PASS" or "FAIL"
    detail: str = ""


@dataclass
class AuditResult:
    phase_id: str
    attempt: int
    overall: str  # "PASS" or "FAIL"
    trust_level: str  # "NONE", "INTENT_ONLY", "OBSERVED"
    checks: List[Check] = field(default_factory=list)
    timestamp: str = ""

    def to_dict(self) -> dict:
        return {
            "phase_id": self.phase_id,
            "attempt": self.attempt,
            "overall": self.overall,
            "trust_level": self.trust_level,
            "timestamp": self.timestamp,
            "checks": [
                {"name": c.name, "status": c.status, "detail": c.detail}
                for c in self.checks
            ],
        }


# ---------------------------------------------------------------------------
# Trust-level ordering helpers
# ---------------------------------------------------------------------------

TRUST_ORDER = {"NONE": 0, "INTENT_ONLY": 1, "OBSERVED": 2}
VALID_TRUST = set(TRUST_ORDER.keys())

CRITICAL_PREFIXES = (
    "p0", "security", "workflow", "gate", "release", "permission", "anti_fake",
)


def trust_lower(a: str, b: str) -> str:
    """Return the *lower* of two trust levels."""
    return a if TRUST_ORDER.get(a, 0) <= TRUST_ORDER.get(b, 0) else b


def is_critical_phase(phase_id: str) -> bool:
    lower = phase_id.lower()
    return any(lower.startswith(p) for p in CRITICAL_PREFIXES)


# ---------------------------------------------------------------------------
# Utility functions (all safe-fail)
# ---------------------------------------------------------------------------

def validate_phase_id(phase_id: str) -> None:
    """Validate phase_id format; block path traversal."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", phase_id):
        raise SystemExit(f"Invalid phase_id: {phase_id}")


def validate_attempt(raw_attempt: str) -> int:
    """Validate and return attempt as int."""
    try:
        attempt = int(raw_attempt)
    except (TypeError, ValueError):
        raise SystemExit(f"Invalid attempt: {raw_attempt}")
    if attempt < 1:
        raise SystemExit(f"Invalid attempt: {raw_attempt}; must be positive integer")
    return attempt


def safe_load_json(path: str) -> Tuple[Optional[dict], Optional[str]]:
    """Safely load JSON.  Returns (data, error).  error=None means success."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f), None
    except FileNotFoundError:
        return None, "文件不存在"
    except json.JSONDecodeError as e:
        return None, f"JSON 解析失败: {e}"
    except Exception as e:
        return None, f"读取失败: {e}"


def file_exists(path: str) -> bool:
    return os.path.isfile(path)


def read_lines(path: str) -> list:
    """Read all lines from a file; return empty list on failure."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.readlines()
    except Exception:
        return []


def sha256_file(path: str) -> str:
    """Compute SHA-256 hex digest of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_ts(value: str) -> datetime:
    """Parse ISO 8601 timestamp, tolerating Z suffix."""
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)


# ---------------------------------------------------------------------------
# Per-receipt validation helper
# ---------------------------------------------------------------------------

def _check_receipt(
    receipt: dict,
    expected_role: str,
    phase_id: str,
    attempt: int,
) -> List[Check]:
    """Validate a single delegation receipt.  Returns a list of Checks."""
    checks: List[Check] = []

    role = receipt.get("role")
    checks.append(Check(
        name=f"receipt.{expected_role}.role",
        status="PASS" if role == expected_role else "FAIL",
        detail=f"expected={expected_role}, got={role}",
    ))

    r_pid = receipt.get("phase_id")
    checks.append(Check(
        name=f"receipt.{expected_role}.phase_id",
        status="PASS" if r_pid == phase_id else "FAIL",
        detail=f"expected={phase_id}, got={r_pid}",
    ))

    r_att = receipt.get("attempt")
    checks.append(Check(
        name=f"receipt.{expected_role}.attempt",
        status="PASS" if r_att == attempt else "FAIL",
        detail=f"expected={attempt}, got={r_att}",
    ))

    # Support both old (trust_level) and new (delegation_trust_level) formats
    tl = receipt.get("trust_level") or receipt.get("delegation_trust_level")
    checks.append(Check(
        name=f"receipt.{expected_role}.trust_level",
        status="PASS" if tl in VALID_TRUST else "FAIL",
        detail=f"got={tl}",
    ))

    return checks


# ---------------------------------------------------------------------------
# Core audit function
# ---------------------------------------------------------------------------

def audit_phase(phase_id: str, attempt: int) -> AuditResult:
    """
    Audit a single (phase_id, attempt) pair across all eight checks.
    Returns an AuditResult with all individual checks populated.
    """
    result = AuditResult(phase_id=phase_id, attempt=attempt, overall="PASS", trust_level="NONE")

    base = ".phase_control"
    delegation_dir = os.path.join(base, "delegations")
    log_dir = os.path.join(base, "logs")
    evidence_dir = os.path.join(base, "evidence")
    verdict_dir = os.path.join(base, "verdicts")

    # ------------------------------------------------------------------
    # 1. Worker Delegation Intent Receipt
    # ------------------------------------------------------------------
    worker_path = os.path.join(delegation_dir, f"{phase_id}_attempt_{attempt}_worker.json")
    worker_data, worker_err = safe_load_json(worker_path)
    worker_trust = "NONE"

    if worker_err is not None:
        result.checks.append(Check(name="check1.worker_receipt", status="FAIL", detail=worker_err))
    else:
        assert worker_data is not None  # guarded by worker_err check
        result.checks.append(Check(name="check1.worker_receipt", status="PASS", detail="loaded"))
        result.checks.extend(_check_receipt(worker_data, "worker", phase_id, attempt))
        wt = worker_data.get("trust_level")
        if wt in VALID_TRUST:
            worker_trust = wt

    # ------------------------------------------------------------------
    # 2. Verifier Delegation Intent Receipt
    # ------------------------------------------------------------------
    verifier_path = os.path.join(delegation_dir, f"{phase_id}_attempt_{attempt}_verifier.json")
    verifier_data, verifier_err = safe_load_json(verifier_path)
    verifier_trust = "NONE"

    if verifier_err is not None:
        result.checks.append(Check(name="check2.verifier_receipt", status="FAIL", detail=verifier_err))
    else:
        assert verifier_data is not None  # guarded by verifier_err check
        result.checks.append(Check(name="check2.verifier_receipt", status="PASS", detail="loaded"))
        result.checks.extend(_check_receipt(verifier_data, "verifier", phase_id, attempt))
        vt = verifier_data.get("trust_level")
        if vt in VALID_TRUST:
            verifier_trust = vt

    # ------------------------------------------------------------------
    # 3. Command Log
    # ------------------------------------------------------------------
    cmd_log_path = os.path.join(log_dir, f"{phase_id}_attempt_{attempt}.commands.jsonl")

    if not file_exists(cmd_log_path):
        result.checks.append(Check(name="check3.command_log", status="FAIL", detail="文件不存在"))
    else:
        lines = read_lines(cmd_log_path)
        if not lines:
            result.checks.append(Check(name="check3.command_log", status="FAIL", detail="文件为空"))
        else:
            cmd_ok = True
            cmd_details: list[str] = []
            for idx, line in enumerate(lines):
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError as e:
                    cmd_ok = False
                    cmd_details.append(f"line {idx+1}: JSON 解析失败: {e}")
                    continue

                for required_field in ("phase_id", "attempt", "command", "exit_code", "runner", "started_at", "ended_at"):
                    if required_field not in entry:
                        cmd_ok = False
                        cmd_details.append(f"line {idx+1}: 缺少字段 {required_field}")

                if entry.get("phase_id") != phase_id:
                    cmd_ok = False
                    cmd_details.append(f"line {idx+1}: phase_id 不匹配")
                if entry.get("attempt") != attempt:
                    cmd_ok = False
                    cmd_details.append(f"line {idx+1}: attempt 不匹配")
                if entry.get("runner") != "hmte exec":
                    cmd_ok = False
                    cmd_details.append(f"line {idx+1}: runner={entry.get('runner')}")
                if not isinstance(entry.get("exit_code"), int):
                    cmd_ok = False
                    cmd_details.append(f"line {idx+1}: exit_code 非整数")

                # time ordering
                sa = entry.get("started_at")
                ea = entry.get("ended_at")
                if sa and ea:
                    try:
                        if parse_ts(sa) > parse_ts(ea):
                            cmd_ok = False
                            cmd_details.append(f"line {idx+1}: started_at > ended_at")
                    except Exception:
                        cmd_ok = False
                        cmd_details.append(f"line {idx+1}: 时间戳解析失败")

            result.checks.append(Check(
                name="check3.command_log",
                status="PASS" if cmd_ok else "FAIL",
                detail="; ".join(cmd_details) if cmd_details else f"{len(lines)} entries ok",
            ))

    # ------------------------------------------------------------------
    # 4. Evidence Bundle
    # ------------------------------------------------------------------
    evidence_path = os.path.join(evidence_dir, f"{phase_id}_attempt_{attempt}.json")
    evidence_data, evidence_err = safe_load_json(evidence_path)

    if evidence_err is not None:
        result.checks.append(Check(name="check4.evidence", status="FAIL", detail=evidence_err))
    else:
        assert evidence_data is not None  # guarded by evidence_err check
        missing = [f for f in ("phase_id", "attempt", "status", "timestamp") if f not in evidence_data]
        if missing:
            result.checks.append(Check(name="check4.evidence", status="FAIL", detail=f"缺少字段: {missing}"))
        else:
            mismatches = []
            if evidence_data.get("phase_id") != phase_id:
                mismatches.append("phase_id 不匹配")
            if evidence_data.get("attempt") != attempt:
                mismatches.append("attempt 不匹配")
            if mismatches:
                result.checks.append(Check(name="check4.evidence", status="FAIL", detail="; ".join(mismatches)))
            else:
                result.checks.append(Check(name="check4.evidence", status="PASS", detail="loaded"))

    # ------------------------------------------------------------------
    # 5. Verdict
    # ------------------------------------------------------------------
    verdict_path = os.path.join(verdict_dir, f"{phase_id}_attempt_{attempt}.json")
    verdict_data, verdict_err = safe_load_json(verdict_path)
    verdict_status: Optional[str] = None

    if verdict_err is not None:
        result.checks.append(Check(name="check5.verdict", status="FAIL", detail=verdict_err))
    else:
        assert verdict_data is not None  # guarded by verdict_err check
        verdict_status = verdict_data.get("status")
        if verdict_status not in ("PASS", "FAIL", "BLOCK"):
            result.checks.append(Check(name="check5.verdict", status="FAIL", detail=f"status={verdict_status}"))
        else:
            result.checks.append(Check(name="check5.verdict", status="PASS", detail=f"status={verdict_status}"))

    # ------------------------------------------------------------------
    # 6. Adversarial Scorecard
    # ------------------------------------------------------------------
    if verdict_data is not None and verdict_status is not None:
        scorecard = verdict_data.get("adversarial_scorecard")
        if verdict_status == "PASS":
            if scorecard is None:
                result.checks.append(Check(name="check6.scorecard", status="FAIL", detail="PASS verdict 缺少 adversarial_scorecard"))
            else:
                sc_ok = True
                sc_details: list[str] = []

                cp = scorecard.get("criteria_passed")
                if not cp:
                    sc_ok = False
                    sc_details.append("criteria_passed 为空")

                cf = scorecard.get("criteria_failed")
                if cf:
                    sc_ok = False
                    sc_details.append("criteria_failed 非空")

                for req in ("evidence_paths", "residual_risks", "re_verification_conclusion"):
                    if req not in scorecard:
                        sc_ok = False
                        sc_details.append(f"缺少 {req}")

                result.checks.append(Check(
                    name="check6.scorecard",
                    status="PASS" if sc_ok else "FAIL",
                    detail="; ".join(sc_details) if sc_details else "ok",
                ))
        elif verdict_status in ("FAIL", "BLOCK"):
            has_criteria_failed = bool(scorecard and scorecard.get("criteria_failed"))
            has_blockers = bool(verdict_data.get("blockers"))
            if not has_criteria_failed and not has_blockers:
                result.checks.append(Check(
                    name="check6.scorecard",
                    status="FAIL",
                    detail="FAIL/BLOCK verdict 缺少 criteria_failed 和 blockers",
                ))
            else:
                result.checks.append(Check(name="check6.scorecard", status="PASS", detail="ok"))
    else:
        result.checks.append(Check(name="check6.scorecard", status="FAIL", detail="无法检查 scorecard（verdict 缺失或无效）"))

    # ------------------------------------------------------------------
    # 7. Timeline consistency
    # ------------------------------------------------------------------
    tl_ok = True
    tl_details: list[str] = []

    # We need worker delegated_at, evidence timestamp, verdict timestamp
    if worker_data is None or evidence_data is None or verdict_data is None:
        tl_ok = False
        tl_details.append("缺少必要数据无法校验时间线")
    else:
        w_da = worker_data.get("delegated_at")
        e_ts = evidence_data.get("timestamp")
        v_ts = verdict_data.get("timestamp")

        if not w_da or not e_ts or not v_ts:
            tl_ok = False
            tl_details.append("缺少时间戳字段")
        else:
            try:
                w_dt = parse_ts(w_da)
                e_dt = parse_ts(e_ts)
                v_dt = parse_ts(v_ts)
                if w_dt > e_dt:
                    tl_ok = False
                    tl_details.append(f"delegated_at ({w_da}) > evidence.timestamp ({e_ts})")
                if e_dt > v_dt:
                    tl_ok = False
                    tl_details.append(f"evidence.timestamp ({e_ts}) > verdict.timestamp ({v_ts})")
            except Exception as exc:
                tl_ok = False
                tl_details.append(f"时间戳解析异常: {exc}")

    result.checks.append(Check(
        name="check7.timeline",
        status="PASS" if tl_ok else "FAIL",
        detail="; ".join(tl_details) if tl_details else "chronological",
    ))

    # ------------------------------------------------------------------
    # 8. SHA-256 consistency
    # ------------------------------------------------------------------
    strict_hash = os.environ.get("HMTE_STRICT_HASH", "").lower() == "true"

    if verdict_data is not None:
        for hash_field, target_path in [
            ("evidence_sha256", evidence_path),
            ("command_log_sha256", cmd_log_path),
        ]:
            expected_hash = verdict_data.get(hash_field)
            if expected_hash:
                if file_exists(target_path):
                    actual = sha256_file(target_path)
                    if actual == expected_hash:
                        result.checks.append(Check(name=f"check8.{hash_field}", status="PASS", detail="hash match"))
                    else:
                        result.checks.append(Check(
                            name=f"check8.{hash_field}", status="FAIL",
                            detail=f"expected={expected_hash[:16]}… got={actual[:16]}…",
                        ))
                else:
                    result.checks.append(Check(name=f"check8.{hash_field}", status="FAIL", detail="目标文件不存在"))
            else:
                # hash field missing in verdict
                if strict_hash:
                    result.checks.append(Check(name=f"check8.{hash_field}", status="FAIL", detail="verdict 缺少该哈希字段（strict mode）"))
                else:
                    result.checks.append(Check(name=f"check8.{hash_field}", status="PASS", detail="legacy: 字段缺失，兼容通过"))

    # ------------------------------------------------------------------
    # HMTE_REQUIRE_OBSERVED check
    # ------------------------------------------------------------------
    require_observed = os.environ.get("HMTE_REQUIRE_OBSERVED", "").lower() == "true"
    if require_observed and is_critical_phase(phase_id):
        if result.trust_level != "OBSERVED":
            # we haven't set trust_level yet; compute below then re-check
            pass  # deferred to after trust computation

    # ------------------------------------------------------------------
    # Compute composite trust level
    # ------------------------------------------------------------------
    composite_trust = trust_lower(worker_trust, verifier_trust)
    result.trust_level = composite_trust

    # Now enforce HMTE_REQUIRE_OBSERVED if applicable
    if require_observed and is_critical_phase(phase_id):
        if composite_trust != "OBSERVED":
            result.checks.append(Check(
                name="check_observed.requirement",
                status="FAIL",
                detail=f"关键阶段 {phase_id} 要求 OBSERVED，当前 {composite_trust}",
            ))

    # ------------------------------------------------------------------
    # Overall verdict
    # ------------------------------------------------------------------
    if any(c.status == "FAIL" for c in result.checks):
        result.overall = "FAIL"
    else:
        result.overall = "PASS"

    return result


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="HTE Anti-Fake Audit Flow")
    parser.add_argument("phase_id", help="Phase ID to audit")
    parser.add_argument("attempt", help="Attempt number (1-indexed)")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    phase_id = args.phase_id
    validate_phase_id(phase_id)
    attempt = validate_attempt(args.attempt)

    result = audit_phase(phase_id, attempt)
    result.timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if args.json:
        print(json.dumps(result.to_dict(), ensure_ascii=False, indent=2))
    else:
        icon = "✅" if result.overall == "PASS" else "❌"
        print(f"{icon} {result.phase_id} attempt {result.attempt}: {result.overall} (trust: {result.trust_level})")
        for c in result.checks:
            ci = "✅" if c.status == "PASS" else "❌"
            detail = f": {c.detail}" if c.detail else ""
            print(f"  {ci} {c.name}{detail}")

    raise SystemExit(0 if result.overall == "PASS" else 1)
