#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_classical_prove_pipeline.sh
#
# Phase 2 (classical) of the benchmark workflow:
#   1. scarb prove   → STARK proof (stwo-cairo, no recursion)
#   2. scarb verify  → verification
#
# Expected environment (set by run_execute_pipeline.sh or caller):
#   PROGRAM_ID  - e.g. "fibonacci"
#   RUN_DIR     - path to the current run artefacts directory
#   PKG_DIR     - path to the generated Scarb package
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

[[ -n "${PROGRAM_ID:-}" ]] || die "PROGRAM_ID not set"
[[ -n "${RUN_DIR:-}" ]]    || die "RUN_DIR not set"
[[ -d "${RUN_DIR}" ]]      || die "RUN_DIR does not exist: ${RUN_DIR}"
[[ -n "${PKG_DIR:-}" ]]    || die "PKG_DIR not set"
[[ -d "${PKG_DIR}" ]]      || die "PKG_DIR does not exist: ${PKG_DIR}"

# ---- Prove ----
info "Running scarb prove on ${PROGRAM_ID}…"

PROVE_ARGS=(prove --execute --target bootloader)
[[ -n "${PROGRAM_ARGS:-}" ]] && PROVE_ARGS+=(--arguments "${PROGRAM_ARGS}")

(cd "${PKG_DIR}" && scarb_run "${PROVE_ARGS[@]}") \
    2>&1 | tee "${RUN_DIR}/logs/prove.log"

# ---- Locate proof file ----
EXEC_BASE="${PKG_DIR}/target/execute/${PROGRAM_ID}"
LATEST_EXEC="$(ls -1d "${EXEC_BASE}"/execution* 2>/dev/null | sort -V | tail -n1)" \
    || die "No execution output found under ${EXEC_BASE}"
PROOF_FILE="$(find "${LATEST_EXEC}" -path '*/proof/proof.json' -o -name 'proof.json' 2>/dev/null | head -n1)"

[[ -n "${PROOF_FILE}" && -f "${PROOF_FILE}" ]] \
    || die "proof.json not found under ${LATEST_EXEC}"

cp "${PROOF_FILE}" "${RUN_DIR}/base_proof/proof.json"
info "Proof saved ($(du -h "${RUN_DIR}/base_proof/proof.json" | cut -f1))"

# ---- Verify ----
info "Running scarb verify on ${PROGRAM_ID}…"

(cd "${PKG_DIR}" && scarb_run verify --proof-file "${PROOF_FILE}") \
    2>&1 | tee "${RUN_DIR}/logs/verify.log"

info "Classical prove pipeline complete."

export PROGRAM_ID RUN_DIR
