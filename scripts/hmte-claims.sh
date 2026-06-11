#!/usr/bin/env bash
# hmte-claims.sh - TAF Capability Declaration (legacy hmte CLI)
#
# Purpose: Output structured capability declarations that clarify TAF boundaries
# and requirements. This script declares what TAF provides and what it requires
# from external systems (like Hermes Agent Runtime).
#
# TriAgentFlow / TAF is a file-based workflow protocol, NOT a complete standalone agent runtime.
# Real Worker/Verifier execution depends on Hermes delegate_task or external
# Agent environment with OBSERVED delegation capabilities.

echo "workflow_mode: FILE_PROTOCOL"
echo "agent_runtime: EXTERNAL_HERMES_REQUIRED"
echo "delegation_proof: INTENT_ONLY"
echo "observed_delegation: UNAVAILABLE"
echo "phase_gate: ENABLED"
echo "final_audit: MANUAL"
echo "protocol_lint: ENABLED"
echo "team_rules: ENABLED"
