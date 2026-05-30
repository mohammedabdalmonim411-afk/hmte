#!/usr/bin/env bash
# hmte-claims.sh - HTE v1.4 Capability Declaration
#
# Purpose: Output structured capability declarations that clarify HTE boundaries
# and requirements. This script declares what HTE provides and what it requires
# from external systems (like Hermes Agent Runtime).
#
# HTE is a file-based workflow protocol, NOT a complete standalone agent runtime.
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
