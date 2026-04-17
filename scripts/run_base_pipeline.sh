#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_base_pipeline.sh <path/to/program.cairo> [--args "<arguments>"]
#
# 1. Prepares the Scarb package (idempotent).
# 2. Executes the program and generates a STWO proof in one shot.
# 3. Verifies the proof.
#
# All artefacts are collected under artifacts/<program_id>/runs/<run_id>/.
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- Parse arguments ----
SOURCE_FILE=""
PROGRAM_ARGS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --args) PROGRAM_ARGS="$2"; shift 2 ;;
        *)
            [[ -z "${SOURCE_FILE}" ]] || die "Unexpected argument: $1"
            SOURCE_FILE="$1"; shift ;;
    esac
done
[[ -n "${SOURCE_FILE}" ]] || die "Usage: $0 <path/to/program.cairo> [--args \"<arguments>\"]"

SOURCE_FILE="$(realpath "${SOURCE_FILE}")"
PROGRAM_ID="$(program_id_from_source "${SOURCE_FILE}")"
PKG_DIR="$(gen_pkg_dir "${PROGRAM_ID}")"

# ---- Prepare package ----
bash "${SCRIPT_DIR}/prepare_program.sh" "${SOURCE_FILE}"

# ---- Create run directory ----
RUN_DIR="$(create_run_dir "${PROGRAM_ID}")"
info "Run directory: ${RUN_DIR}"

echo "${PROGRAM_ARGS}" > "${RUN_DIR}/inputs/arguments.txt"

# Copy compiled artefacts
copy_if_exists "${PKG_DIR}/Scarb.toml" "${RUN_DIR}/compiled/Scarb.toml"
copy_if_exists "${PKG_DIR}/target/dev/${PROGRAM_ID}.executable.json" \
               "${RUN_DIR}/compiled/${PROGRAM_ID}.executable.json"

# ---- Clean previous executions to get a deterministic execution id ----
(cd "${PKG_DIR}" && scarb clean) 2>&1 | tee -a "${RUN_DIR}/logs/clean.log"

# ---- Execute + Prove (scarb prove --execute) ----
info "Executing and proving ${PROGRAM_ID}…"
PROVE_ARGS=(--execute --print-program-output --print-resource-usage)
[[ -z "${PROGRAM_ARGS}" ]] || PROVE_ARGS+=(--arguments "${PROGRAM_ARGS}")

(cd "${PKG_DIR}" && scarb prove "${PROVE_ARGS[@]}") \
    2>&1 | tee "${RUN_DIR}/logs/prove.log"

# The execution id is always 1 because we cleaned before running.
EXEC_ID="1"
EXEC_DIR="${PKG_DIR}/target/execute/${PROGRAM_ID}/execution${EXEC_ID}"

[[ -d "${EXEC_DIR}" ]] || die "Execution directory not found: ${EXEC_DIR}"

# Collect VM artefacts
copy_if_exists "${EXEC_DIR}/prover_input.json" "${RUN_DIR}/vm/prover_input.json"

# Collect proof
PROOF_FILE="${EXEC_DIR}/proof/proof.json"
if [[ -f "${PROOF_FILE}" ]]; then
    cp "${PROOF_FILE}" "${RUN_DIR}/base_proof/proof.json"
    info "Proof saved ($(du -h "${RUN_DIR}/base_proof/proof.json" | cut -f1))"
else
    die "proof.json not found after scarb prove"
fi

# ---- Verify ----
info "Verifying proof…"
(cd "${PKG_DIR}" && scarb verify --execution-id "${EXEC_ID}") \
    2>&1 | tee "${RUN_DIR}/logs/verify.log"

info "Base pipeline complete. Artefacts in ${RUN_DIR}"

# Export variables for downstream scripts (run_workflow.sh)
export PROGRAM_ID RUN_DIR PROOF_FILE EXEC_ID PKG_DIR
