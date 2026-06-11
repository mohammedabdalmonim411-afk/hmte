#!/usr/bin/env python3
"""
TriAgentFlow / TAF Orchestrator — 文件协议状态机

架构说明：
  orchestrator不启动Worker/Verifier子Agent。
  它通过文件协议（instruction.json）发出任务请求，
  由外部Leader Agent读取instruction后用delegate_task启动子Agent。
  文件模式下，等待evidence/verdict有硬超时，超时写error。

用法:
  python orchestrator.py run <goal>    # 运行完整工作流（file模式）
  python orchestrator.py resume        # 从上次失败处恢复
  python orchestrator.py status        # 查看当前状态
"""

import json
import os
import subprocess
import sys
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


# ============================================================================
# Data Classes
# ============================================================================

class Phase:
    """阶段定义"""
    def __init__(self, phase_id, name, objective, priority="P0", status="pending",
                 max_retries=2, worker_timeout=1800, verifier_timeout=600,
                 acceptance_criteria=None, context=None,
                 execution_mode=None, parallel_workers=None):
        self.id = phase_id
        self.name = name
        self.objective = objective
        self.priority = priority
        self.status = status
        self.max_retries = max_retries
        self.worker_timeout = worker_timeout
        self.verifier_timeout = verifier_timeout
        self.acceptance_criteria = acceptance_criteria or []
        self.context = context or {}
        self.execution_mode = execution_mode or "sequential"
        self.parallel_workers = parallel_workers or []

    def to_dict(self):
        # Output canonical schema: phase_id, goal, acceptance_criteria
        d = {
            "phase_id": self.id,
            "goal": self.objective,
            "acceptance_criteria": self.acceptance_criteria,
            "priority": self.priority,
            "status": self.status,
            "max_retries": self.max_retries,
            "worker_timeout": self.worker_timeout,
            "verifier_timeout": self.verifier_timeout,
            "context": self.context
        }
        if self.execution_mode and self.execution_mode != "sequential":
            d["execution_mode"] = self.execution_mode
        if self.parallel_workers:
            d["parallel_workers"] = self.parallel_workers
        return d

    @classmethod
    def from_dict(cls, d):
        # v1.8: Accept canonical (phase_id/goal/acceptance_criteria) and
        # legacy (id/name/objective/description) schema without fragile
        # co_varnames introspection.
        phase_id = d.get("phase_id") or d.get("id") or d.get("name")
        goal = d.get("goal") or d.get("objective") or d.get("description")
        name = d.get("name") or phase_id
        return cls(
            phase_id=phase_id,
            name=name,
            objective=goal,
            priority=d.get("priority", "P0"),
            status=d.get("status", "pending"),
            max_retries=d.get("max_retries", 2),
            worker_timeout=d.get("worker_timeout", 1800),
            verifier_timeout=d.get("verifier_timeout", 600),
            acceptance_criteria=d.get("acceptance_criteria", []),
            context=d.get("context", {}),
            execution_mode=d.get("execution_mode"),
            parallel_workers=d.get("parallel_workers"),
        )


class PhaseResult:
    """单个阶段的执行结果"""
    def __init__(self, phase_id):
        self.phase_id = phase_id
        self.verdict = None
        self.evidence = None
        self.verdict_details = None
        self.error = None
        self.attempt = 0
        self.start_time = None
        self.end_time = None

    def to_dict(self):
        return {"phase_id": self.phase_id, "verdict": self.verdict,
                "evidence": self.evidence, "verdict_details": self.verdict_details,
                "error": self.error, "attempt": self.attempt,
                "start_time": self.start_time, "end_time": self.end_time}


class VerdictResult:
    """Verifier 返回的验证结果"""
    def __init__(self, status, phase_id="", timestamp="", details=None,
                 issues=None, recommendations=None, error=None):
        self.status = status
        self.phase_id = phase_id
        self.timestamp = timestamp
        self.details = details or {}
        self.issues = issues or []
        self.recommendations = recommendations or []
        self.error = error


class WorkflowResult:
    """完整工作流的执行结果"""
    def __init__(self, goal):
        self.goal = goal
        self.status = "RUNNING"
        self.phase_results = []
        self.start_time = None
        self.end_time = None
        self.failed_phase = None
        self.blocked_phase = None

    def to_dict(self):
        return {"goal": self.goal, "status": self.status,
                "phase_results": [pr.to_dict() for pr in self.phase_results],
                "start_time": self.start_time, "end_time": self.end_time,
                "failed_phase": self.failed_phase, "blocked_phase": self.blocked_phase}

    def add_phase_result(self, result):
        self.phase_results.append(result)


# ============================================================================
# File I/O Helpers
# ============================================================================

def read_json_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def write_json_file(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def wait_for_file(path, timeout=1800, poll_interval=5):
    """轮询等待目标文件出现，超时返回 None"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    json.load(f)
                return path
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(poll_interval)
    return None


# ============================================================================
# Core Orchestrator
# ============================================================================

class Orchestrator:
    """
    TriAgentFlow / TAF 核心编排引擎（hmte 为历史命令前缀）。
    按顺序执行 phases，每个阶段包含 Worker→evidence→Verifier→verdict 循环。
    """
    VALID_VERDICTS = {"PASS", "FAIL", "BLOCK"}
    POLL_INTERVAL = 5

    def __init__(self, project_root="."):
        self.root = Path(project_root)
        self.control_dir = self.root / ".phase_control"
        self.state_file = self.control_dir / "state.json"
        self.phases_file = self.control_dir / "phases.json"
        self._ensure_dirs()

    def _ensure_dirs(self):
        for subdir in ["evidence", "verdicts", "instructions", "state", "errors"]:
            (self.control_dir / subdir).mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def run_workflow(self, goal):
        """执行完整工作流，返回 WorkflowResult"""
        result = WorkflowResult(goal=goal)
        result.start_time = now_iso()
        self._save_state({"goal": goal, "status": "RUNNING",
                          "current_phase_index": 0, "started_at": result.start_time,
                          "updated_at": result.start_time})
        self._log_event("workflow_started", {"goal": goal, "timestamp": result.start_time})
        phases = self._load_phases()
        if not phases:
            result.status = "FAILED"
            result.end_time = now_iso()
            self._save_state({**self._read_state(), "status": "FAILED",
                              "error": "No phases found", "updated_at": result.end_time})
            return result

        for idx, phase in enumerate(phases):
            self._save_state({**self._read_state(), "current_phase_index": idx,
                              "current_phase_id": phase.id, "phase_status": "running",
                              "updated_at": now_iso()})
            phase_result = self.run_phase(phase)
            result.add_phase_result(phase_result)
            if phase_result.verdict == "PASS":
                continue
            elif phase_result.verdict == "FAIL":
                result.status = "FAILED"
                result.failed_phase = phase.id
                break
            elif phase_result.verdict == "BLOCK":
                result.status = "BLOCKED"
                result.blocked_phase = phase.id
                break
            else:
                result.status = "FAILED"
                result.failed_phase = phase.id
                break

        if result.status == "RUNNING":
            result.status = "COMPLETED"
        result.end_time = now_iso()
        self._save_state({**self._read_state(), "status": result.status,
                          "failed_phase": result.failed_phase,
                          "blocked_phase": result.blocked_phase,
                          "updated_at": result.end_time})
        write_json_file(str(self.control_dir / "state" / "workflow_result.json"),
                        result.to_dict())
        return result

    def run_phase(self, phase):
        """执行单个 phase：Worker→evidence→Verifier→verdict，支持重试"""
        phase_result = PhaseResult(phase_id=phase.id)

        # v1.7: Log parallel phase start
        if phase.execution_mode == "parallel_safe" and phase.parallel_workers:
            self._log_event("parallel_phase_started", {
                "phase_id": phase.id,
                "execution_mode": phase.execution_mode,
                "worker_count": len(phase.parallel_workers),
                "worker_ids": [w.get("worker_id", "") for w in phase.parallel_workers],
                "timestamp": now_iso()
            })

        for attempt in range(phase.max_retries + 1):
            phase_result.attempt = attempt + 1
            phase_result.start_time = now_iso()
            try:
                # v1.7: For parallel_safe, write per-shard instructions
                if phase.execution_mode == "parallel_safe" and phase.parallel_workers:
                    for w in phase.parallel_workers:
                        wid = w.get("worker_id", "unknown")
                        shard_ev_path = str(self.control_dir / "evidence" / f"{phase.id}_{wid}_attempt_{attempt + 1}.json")
                        self._cleanup_stale(shard_ev_path)
                        shard_instr = {
                            "task_id": f"{phase.id}_{wid}_worker_{attempt}",
                            "role": "worker",
                            "worker_id": wid,
                            "goal": w.get("scope", phase.objective),
                            "context": phase.context,
                            "output_path": shard_ev_path,
                            "timeout": phase.worker_timeout,
                            "created_at": now_iso(),
                            "status": "PENDING"
                        }
                        write_json_file(str(self.control_dir / "instructions" /
                                            f"{phase.id}_{wid}_worker_{attempt}.json"), shard_instr)
                        self._log_event("worker_shard_delegated", {
                            "phase_id": phase.id, "worker_id": wid,
                            "attempt": attempt + 1, "timestamp": now_iso()
                        })

                    # Wait for ALL shard evidence
                    all_found = True
                    for w in phase.parallel_workers:
                        wid = w.get("worker_id", "unknown")
                        shard_ev_path = str(self.control_dir / "evidence" / f"{phase.id}_{wid}_attempt_{attempt + 1}.json")
                        result = wait_for_file(shard_ev_path, timeout=phase.worker_timeout,
                                               poll_interval=self.POLL_INTERVAL)
                        if result is None:
                            all_found = False
                            phase_result.verdict = "FAIL"
                            phase_result.error = f"Worker shard {wid} timeout after {phase.worker_timeout}s"
                            break
                        self._log_event("worker_shard_evidence_ready", {
                            "phase_id": phase.id, "worker_id": wid,
                            "attempt": attempt + 1, "timestamp": now_iso()
                        })

                    if not all_found:
                        phase_result.end_time = now_iso()
                        if attempt < phase.max_retries:
                            continue
                        return phase_result

                    # Write verifier instruction for join verification
                    vd_path = str(self.control_dir / "verdicts" / f"{phase.id}_attempt_{attempt + 1}.json")
                    verifier_instr = {
                        "task_id": f"{phase.id}_verifier_{attempt}",
                        "role": "verifier",
                        "goal": phase.objective,
                        "evidence_paths": [
                            str(self.control_dir / "evidence" / f"{phase.id}_{w['worker_id']}_attempt_{attempt + 1}.json")
                            for w in phase.parallel_workers
                        ],
                        "acceptance_criteria": phase.acceptance_criteria,
                        "output_path": vd_path,
                        "timeout": phase.verifier_timeout,
                        "created_at": now_iso(),
                        "status": "PENDING",
                        "join_verification": True
                    }
                    write_json_file(str(self.control_dir / "instructions" /
                                        f"{phase.id}_verifier_{attempt}.json"), verifier_instr)

                    # Wait for verdict
                    actual_vd = wait_for_file(vd_path, timeout=phase.verifier_timeout,
                                              poll_interval=self.POLL_INTERVAL)
                    if actual_vd is None:
                        phase_result.verdict = "FAIL"
                        phase_result.error = f"Verifier timeout after {phase.verifier_timeout}s"
                        phase_result.end_time = now_iso()
                        if attempt < phase.max_retries:
                            continue
                        return phase_result

                    vr = self.check_verdict(actual_vd, phase_id=phase.id, attempt=attempt + 1)
                    phase_result.verdict = vr.status
                    phase_result.verdict_details = {
                        "phase_id": vr.phase_id, "details": vr.details,
                        "issues": vr.issues, "recommendations": vr.recommendations,
                        "error": vr.error
                    }
                    phase_result.end_time = now_iso()

                    self._log_event("join_verification_result", {
                        "phase_id": phase.id, "attempt": attempt + 1,
                        "verdict": vr.status, "timestamp": now_iso()
                    })
                    self._log_event("parallel_phase_gate_result", {
                        "phase_id": phase.id, "attempt": attempt + 1,
                        "verdict": vr.status, "timestamp": now_iso()
                    })

                    if vr.status in ("PASS", "BLOCK"):
                        return phase_result
                    if attempt < phase.max_retries:
                        continue
                    return phase_result

                else:
                    # Sequential mode — original logic
                    # 1) 写 Worker 指令
                    ev_path = str(self.control_dir / "evidence" / f"{phase.id}_attempt_{attempt + 1}.json")
                    self._cleanup_stale(ev_path)
                    worker_instr = {"task_id": f"{phase.id}_worker_{attempt}", "role": "worker",
                                    "goal": phase.objective, "context": phase.context,
                                    "output_path": ev_path, "timeout": phase.worker_timeout,
                                    "created_at": now_iso(), "status": "PENDING"}
                    write_json_file(str(self.control_dir / "instructions" /
                                        f"{phase.id}_worker_{attempt}.json"), worker_instr)

                    # 2) 等待 evidence
                    actual_ev = wait_for_file(ev_path, timeout=phase.worker_timeout,
                                              poll_interval=self.POLL_INTERVAL)
                    if actual_ev is None:
                        phase_result.verdict = "FAIL"
                        phase_result.error = f"Worker timeout after {phase.worker_timeout}s (attempt {attempt + 1})"
                        phase_result.end_time = now_iso()
                        if attempt < phase.max_retries:
                            continue
                        return phase_result

                    # 3) 读 evidence
                    phase_result.evidence = read_json_file(actual_ev)

                    # 4) 写 Verifier 指令
                    vd_path = str(self.control_dir / "verdicts" / f"{phase.id}_attempt_{attempt + 1}.json")
                    verifier_instr = {"task_id": f"{phase.id}_verifier_{attempt}", "role": "verifier",
                                      "goal": phase.objective, "evidence_path": actual_ev,
                                      "acceptance_criteria": phase.acceptance_criteria,
                                      "output_path": vd_path, "timeout": phase.verifier_timeout,
                                      "created_at": now_iso(), "status": "PENDING"}
                    write_json_file(str(self.control_dir / "instructions" /
                                        f"{phase.id}_verifier_{attempt}.json"), verifier_instr)

                    # 5) 等待 verdict
                    actual_vd = wait_for_file(vd_path, timeout=phase.verifier_timeout,
                                              poll_interval=self.POLL_INTERVAL)
                    if actual_vd is None:
                        phase_result.verdict = "FAIL"
                        phase_result.error = f"Verifier timeout after {phase.verifier_timeout}s (attempt {attempt + 1})"
                        phase_result.end_time = now_iso()
                        if attempt < phase.max_retries:
                            continue
                        return phase_result

                    # 6) 解析 verdict
                    vr = self.check_verdict(actual_vd, phase_id=phase.id, attempt=attempt + 1)
                    phase_result.verdict = vr.status
                    phase_result.verdict_details = {"phase_id": vr.phase_id, "details": vr.details,
                                                    "issues": vr.issues,
                                                    "recommendations": vr.recommendations,
                                                    "error": vr.error}
                    phase_result.end_time = now_iso()
                    self._log_event("verdict_checked", {"phase_id": phase.id, "attempt": attempt + 1,
                                                         "verdict": vr.status, "timestamp": phase_result.end_time})
                    if vr.status == "PASS":
                        return phase_result
                    if vr.status == "BLOCK":
                        return phase_result
                    # FAIL → retry
                    if attempt < phase.max_retries:
                        continue
                    return phase_result

            except Exception as e:
                phase_result.verdict = "FAIL"
                phase_result.error = f"Exception: {type(e).__name__}: {e}"
                phase_result.end_time = now_iso()
                error_report = {"phase_id": phase.id, "attempt": attempt + 1,
                                "error_type": type(e).__name__, "error_message": str(e),
                                "traceback": traceback.format_exc(), "timestamp": now_iso()}
                write_json_file(str(self.control_dir / "errors" /
                                    f"{phase.id}_attempt_{attempt + 1}.json"), error_report)
                if attempt < phase.max_retries:
                    continue
                return phase_result
        return phase_result

    def run_phase_gate(self, phase_id, attempt):
        """
        调用 phase_gate.sh 进行 anti-fake 审计。
        返回 (passed: bool, output: str)
        """
        candidates = [
            self.root / "src" / "skills" / "hmte" / "scripts" / "phase_gate.sh",
            self.root / "scripts" / "phase_gate.sh",
            Path(__file__).parent / "phase_gate.sh",
        ]
        script = None
        for c in candidates:
            if c.exists():
                script = str(c)
                break
        if script is None:
            return False, "phase_gate.sh not found"

        try:
            result = subprocess.run(
                ["bash", script, phase_id, "--attempt", str(attempt)],
                capture_output=True, text=True, timeout=120,
                cwd=str(self.root)
            )
            output = result.stdout + result.stderr
            return result.returncode == 0, output
        except subprocess.TimeoutExpired:
            return False, "phase_gate.sh timed out after 120s"
        except Exception as e:
            return False, f"phase_gate.sh error: {e}"

    def check_verdict(self, verdict_file, phase_id=None, attempt=None):
        """解析 verdict JSON 文件，先调用 phase_gate，再返回 VerdictResult"""
        if phase_id is not None and attempt is not None:
            passed, output = self.run_phase_gate(phase_id, attempt)
            self._log_event("gate_result", {"phase_id": phase_id, "attempt": attempt,
                                            "passed": passed, "timestamp": now_iso()})
            if not passed:
                return VerdictResult(
                    status="FAIL",
                    phase_id=phase_id or "",
                    error=f"phase_gate failed: {output}"
                )

        try:
            data = read_json_file(verdict_file)
        except json.JSONDecodeError as e:
            return VerdictResult(status="FAIL", error=f"Invalid JSON: {e}")
        except FileNotFoundError:
            return VerdictResult(status="FAIL", error=f"File not found: {verdict_file}")
        except Exception as e:
            return VerdictResult(status="FAIL", error=f"Error reading verdict: {e}")

        for field in ("status", "timestamp", "phase_id"):
            if field not in data:
                return VerdictResult(status="FAIL", error=f"Missing required field: {field}")

        status = data["status"].upper()
        if status not in Orchestrator.VALID_VERDICTS:
            return VerdictResult(status="FAIL", error=f"Invalid status: {status}")

        return VerdictResult(status=status, phase_id=data["phase_id"],
                             timestamp=data["timestamp"],
                             details=data.get("details", {}),
                             issues=data.get("issues", []),
                             recommendations=data.get("recommendations", []))


    def _cleanup_stale(self, path):
        """Rename stale expected output to prevent false completion."""
        import shutil
        p = Path(path)
        if p.exists():
            stale = p.with_suffix(f'.stale.{now_iso().replace(":", "").replace("-", "")}.json')
            try:
                shutil.move(str(p), str(stale))
                self._log_event("stale_evidence_renamed", {
                    "original": path, "stale": str(stale), "timestamp": now_iso()
                })
            except Exception:
                pass

    # ------------------------------------------------------------------
    # Crash Recovery
    # ------------------------------------------------------------------

    def resume_workflow(self):
        """从上次中断处恢复工作流"""
        state = self._read_state()
        if not state:
            print("❌ No saved state found. Use 'run' to start a new workflow.")
            return WorkflowResult(goal="(no state)")

        result = WorkflowResult(goal=state.get("goal", ""))
        result.start_time = now_iso()
        phases = self._load_phases()
        start_index = state.get("current_phase_index", 0)
        prev_status = state.get("status", "RUNNING")

        if prev_status == "RUNNING":
            print(f"▶ Resuming from phase index {start_index}...")
        elif prev_status in ("FAILED", "BLOCKED"):
            print(f"▶ Retrying from phase index {start_index}...")
        else:
            print(f"▶ Status was '{prev_status}', restarting from phase {start_index}...")

        for idx in range(start_index, len(phases)):
            phase = phases[idx]
            self._save_state({**self._read_state(), "current_phase_index": idx,
                              "current_phase_id": phase.id, "phase_status": "running",
                              "status": "RUNNING", "updated_at": now_iso()})
            phase_result = self.run_phase(phase)
            result.add_phase_result(phase_result)
            if phase_result.verdict == "PASS":
                continue
            elif phase_result.verdict == "FAIL":
                result.status = "FAILED"
                result.failed_phase = phase.id
                break
            elif phase_result.verdict == "BLOCK":
                result.status = "BLOCKED"
                result.blocked_phase = phase.id
                break

        if result.status == "RUNNING":
            result.status = "COMPLETED"
        result.end_time = now_iso()
        self._save_state({**self._read_state(), "status": result.status,
                          "updated_at": result.end_time})
        return result

    def get_status(self):
        """获取当前工作流状态"""
        state = self._read_state()
        if not state:
            return {"status": "IDLE", "message": "No active workflow"}
        result_path = self.control_dir / "state" / "workflow_result.json"
        if result_path.exists():
            try:
                return {**state, "workflow_result": read_json_file(str(result_path))}
            except Exception:
                pass
        return state

    # ------------------------------------------------------------------
    # Internal Helpers
    # ------------------------------------------------------------------

    def _load_phases(self):
        if not self.phases_file.exists():
            print(f"⚠ Phases file not found: {self.phases_file}")
            return []
        try:
            data = read_json_file(str(self.phases_file))
            return [Phase.from_dict(p) for p in data.get("phases", [])]
        except Exception as e:
            print(f"❌ Error loading phases: {e}")
            return []

    def _save_state(self, state):
        write_json_file(str(self.state_file), state)

    def _read_state(self):
        if not self.state_file.exists():
            return {}
        try:
            return read_json_file(str(self.state_file))
        except Exception:
            return {}

    def _log_event(self, event_type, data):
        """写入 run ledger 事件到 .phase_control/run_ledger.jsonl"""
        try:
            script_candidates = [
                self.root / "scripts" / "hmte-log-event.sh",
                Path(__file__).parent.parent.parent.parent / "scripts" / "hmte-log-event.sh",
                Path(__file__).parent / "hmte-log-event.sh",
            ]
            script = None
            for c in script_candidates:
                if c.exists():
                    script = str(c)
                    break
            if script is None:
                return

            event_json = json.dumps({"event": event_type, **data}, ensure_ascii=False)
            subprocess.run(["bash", script, event_type, event_json],
                          capture_output=True, text=True, timeout=5, cwd=str(self.root))
        except Exception:
            pass


# ============================================================================
# CLI Entry Point
# ============================================================================

def cmd_run(goal, project_root="."):
    orch = Orchestrator(project_root)
    print(f"🚀 Starting workflow: {goal}")
    print(f"   Root: {os.path.abspath(project_root)}\n")
    result = orch.run_workflow(goal)
    print(f"\n{'=' * 60}")
    print(f"Workflow Status: {result.status}")
    print(f"Phases Executed: {len(result.phase_results)}")
    for pr in result.phase_results:
        icon = {"PASS": "✅", "FAIL": "❌", "BLOCK": "🚧"}.get(pr.verdict, "❓")
        extra = f" (attempt {pr.attempt})" if pr.attempt > 1 else ""
        err = f" - {pr.error}" if pr.error else ""
        print(f"  {icon} {pr.phase_id}: {pr.verdict}{extra}{err}")
    if result.failed_phase:
        print(f"Failed at: {result.failed_phase}")
    if result.blocked_phase:
        print(f"Blocked at: {result.blocked_phase}")
    print("=" * 60)
    return result

def cmd_resume(project_root="."):
    orch = Orchestrator(project_root)
    print("🔄 Resuming workflow...")
    result = orch.resume_workflow()
    print(f"\nWorkflow Status: {result.status}")
    print(f"Phases Executed: {len(result.phase_results)}")
    return result

def cmd_status(project_root="."):
    orch = Orchestrator(project_root)
    status = orch.get_status()
    print("📊 Workflow Status:")
    print(json.dumps(status, indent=2, ensure_ascii=False))
    return status

def main():
    import argparse
    parser = argparse.ArgumentParser(description="TriAgentFlow / TAF Orchestrator - 文件协议状态机")
    subparsers = parser.add_subparsers(dest="command")

    run_parser = subparsers.add_parser("run", help="运行完整工作流")
    run_parser.add_argument("goal", help="工作流目标")
    run_parser.add_argument("--root", default=".", help="项目根目录")
    run_parser.add_argument("--mode", choices=["file", "auto"], default="file",
                            help="file: 写instruction等外部驱动; auto: 需要真实delegate_task adapter")

    resume_parser = subparsers.add_parser("resume", help="从上次失败处恢复")
    resume_parser.add_argument("--root", default=".", help="项目根目录")

    status_parser = subparsers.add_parser("status", help="查看当前状态")
    status_parser.add_argument("--root", default=".", help="项目根目录")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "run":
        if args.mode == "auto":
            print("ERROR: --auto mode requires a real Hermes delegate_task adapter.\n"
                  "Use file-instruction mode (default) or run inside a supported Hermes integration.",
                  file=sys.stderr)
            sys.exit(1)
        cmd_run(args.goal, args.root)
    elif args.command == "resume":
        cmd_resume(args.root)
    elif args.command == "status":
        cmd_status(args.root)

if __name__ == "__main__":
    main()
