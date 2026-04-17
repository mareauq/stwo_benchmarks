#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_recursive_pipeline.sh
#
# Runs the recursive verification layer:
#   1. Produces a proof in cairo-serde format (flat felt array),
#      suitable as input to the stwo_cairo_verifier.
#   2. Executes the stwo_cairo_verifier on that proof.
#   3. Proves the verifier execution (recursive proof).
#   4. Verifies the recursive proof.
#
# Expected environment (set by run_workflow.sh or caller):
#   PROGRAM_ID  - e.g. "fibonacci"
#   RUN_DIR     - path to the current run artefacts directory
#   PKG_DIR     - path to the generated Scarb package for the
#                 user program
#
# Prerequisites:
#   - vendor/stwo-cairo/ must exist (run scripts/setup_vendor.sh)
#   - For step 1, one of:
#       a) stwo-run-and-prove on PATH  (cargo install stwo-run-and-prove)
#       b) A pre-placed cairo-serde proof in $RUN_DIR/recursive_proof/
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VERIFIER_DIR="${REPO_ROOT}/vendor/stwo-cairo/stwo_cairo_verifier"
VERIFIER_FEATURE="${VERIFIER_FEATURE:-qm31_opcode}"

# ---- Validate prerequisites ----
[[ -n "${PROGRAM_ID:-}" ]]  || die "PROGRAM_ID not set"
[[ -n "${RUN_DIR:-}" ]]     || die "RUN_DIR not set"
[[ -d "${RUN_DIR}" ]]       || die "RUN_DIR does not exist: ${RUN_DIR}"
[[ -n "${PKG_DIR:-}" ]]     || die "PKG_DIR not set"

if [[ ! -d "${VERIFIER_DIR}" ]]; then
    info "stwo_cairo_verifier not found at ${VERIFIER_DIR}"
    info "Run: bash scripts/setup_vendor.sh"
    die  "Recursive pipeline requires the vendored verifier."
fi

RECURSIVE_DIR="${RUN_DIR}/recursive_proof"
SERDE_PROOF="${RECURSIVE_DIR}/proof.cairo_serde.json"

COMPILED_PROGRAM="${RUN_DIR}/compiled/${PROGRAM_ID}.executable.json"
[[ -f "${COMPILED_PROGRAM}" ]] || die "Compiled program not found: ${COMPILED_PROGRAM}"

# ---- Read back the arguments used for the base run ----
PROGRAM_ARGS=""
if [[ -f "${RUN_DIR}/inputs/arguments.txt" ]]; then
    PROGRAM_ARGS="$(cat "${RUN_DIR}/inputs/arguments.txt")"
fi

# ----------------------------------------------------------------
# Step 1 — Produce proof in cairo-serde format
#
# scarb prove outputs proof.json (structured JSON).
# The verifier expects --arguments-file with a flat felt252 array.
# stwo-run-and-prove (from proving-utils) can directly run + prove
# a compiled Cairo program and emit the cairo-serde format.
# ----------------------------------------------------------------
if [[ -f "${SERDE_PROOF}" ]]; then
    info "Cairo-serde proof already exists: ${SERDE_PROOF}"
elif command -v stwo-run-and-prove &>/dev/null; then
    info "Generating cairo-serde proof via stwo-run-and-prove…"

    PROVE_ARGS=(
        --program "${COMPILED_PROGRAM}"
        --proof_path "${SERDE_PROOF}"
        --proof-format cairo-serde
        --verify
    )

    # If the program takes arguments, write a program_input file.
    if [[ -n "${PROGRAM_ARGS}" ]]; then
        PROGRAM_INPUT_FILE="${RECURSIVE_DIR}/program_input.json"
        echo "[${PROGRAM_ARGS}]" > "${PROGRAM_INPUT_FILE}"
        PROVE_ARGS+=(--program_input "${PROGRAM_INPUT_FILE}")
    fi

    stwo-run-and-prove "${PROVE_ARGS[@]}" \
        2>&1 | tee "${RUN_DIR}/logs/stwo_run_and_prove.log"

    [[ -f "${SERDE_PROOF}" ]] || die "stwo-run-and-prove did not produce ${SERDE_PROOF}"
    info "Cairo-serde proof generated ($(du -h "${SERDE_PROOF}" | cut -f1))"
else
    info "============================================================"
    info "Cannot produce cairo-serde proof automatically."
    info ""
    info "Install stwo-run-and-prove, then re-run:"
    info "  bash scripts/setup_proving_utils.sh"
    info ""
    info "Or place a pre-converted proof at:"
    info "  ${SERDE_PROOF}"
    info "============================================================"
    die  "Cairo-serde proof not available. See instructions above."
fi

# ----------------------------------------------------------------
# Step 2 — Execute the verifier Cairo program on the serde proof
# ----------------------------------------------------------------
info "Executing stwo_cairo_verifier on the base proof…"
(cd "${VERIFIER_DIR}" && scarb_verifier clean) 2>&1 | tee -a "${RUN_DIR}/logs/recursive_clean.log"

(cd "${VERIFIER_DIR}" && scarb_verifier --profile proving execute \
    --package stwo_cairo_verifier \
    --features "${VERIFIER_FEATURE}" \
    --print-program-output \
    --print-resource-usage \
    --arguments-file "${SERDE_PROOF}") \
    2>&1 | tee "${RUN_DIR}/logs/recursive_execute.log"

VERIFIER_EXEC_DIR="$(ls -1d "${VERIFIER_DIR}/target/execute/stwo_cairo_verifier"/execution* 2>/dev/null \
    | sort -V | tail -n1)" \
    || die "No verifier execution output"
VERIFIER_EXEC_ID="$(basename "${VERIFIER_EXEC_DIR}" | sed 's/execution//')"

info "Verifier execution id: ${VERIFIER_EXEC_ID}"

# ----------------------------------------------------------------
# Step 3 — Prove the verifier execution (recursive proof)
# ----------------------------------------------------------------
info "Proving verifier execution (recursive proof)…"
(cd "${VERIFIER_DIR}" && scarb_verifier prove \
    --execution-id "${VERIFIER_EXEC_ID}" \
    --package stwo_cairo_verifier \
    --features "${VERIFIER_FEATURE}") \
    2>&1 | tee "${RUN_DIR}/logs/recursive_prove.log"

RECURSIVE_PROOF_FILE="${VERIFIER_EXEC_DIR}/proof/proof.json"
if [[ -f "${RECURSIVE_PROOF_FILE}" ]]; then
    cp "${RECURSIVE_PROOF_FILE}" "${RECURSIVE_DIR}/recursive_proof.json"
    info "Recursive proof saved ($(du -h "${RECURSIVE_DIR}/recursive_proof.json" | cut -f1))"
else
    die "Recursive proof.json not generated"
fi

# ----------------------------------------------------------------
# Step 4 — Verify the recursive proof
# ----------------------------------------------------------------
info "Verifying recursive proof…"
(cd "${VERIFIER_DIR}" && scarb_verifier verify \
    --execution-id "${VERIFIER_EXEC_ID}" \
    --package stwo_cairo_verifier) \
    2>&1 | tee "${RUN_DIR}/logs/recursive_verify.log"

info "Recursive pipeline complete. Artefacts in ${RECURSIVE_DIR}"
