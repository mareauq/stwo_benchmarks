#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_workflow.sh <path/to/program.cairo> [--args "<arguments>"]
#                                         [--skip-prove]
#                                         [--classical]
#                                         [--skip-env-check]
#
# Top-level entry point.  Runs both phases:
#   Phase 1  scarb execute
#   Phase 2  prove + verify
#
# Proving modes:
#   (default)    recursive: scarb execute --target bootloader → recursive_prover
#   --classical  classical: scarb execute --target standalone → scarb prove/verify
#   --skip-prove execute only, no proving
#
# Examples:
#   bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10"
#   bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --classical
#   bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --skip-prove
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SOURCE_FILE=""
PROGRAM_ARGS=""
SKIP_PROVE=false
SKIP_CHECK=false
CLASSICAL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --args)           PROGRAM_ARGS="$2"; shift 2 ;;
        --skip-prove)     SKIP_PROVE=true; shift ;;
        --classical)      CLASSICAL=true; shift ;;
        --skip-env-check) SKIP_CHECK=true; shift ;;
        *)
            [[ -z "${SOURCE_FILE}" ]] || die "Unexpected argument: $1"
            SOURCE_FILE="$1"; shift ;;
    esac
done
[[ -n "${SOURCE_FILE}" ]] || die "Usage: $0 <path/to/program.cairo> [--args \"...\"] [--skip-prove] [--classical] [--skip-env-check]"

# ================================================================
# Phase 0 — Environment check
# ================================================================
if [[ "${SKIP_CHECK}" == true ]]; then
    info "Skipping environment check (--skip-env-check)."
else
    info "========== Phase 0: Environment check =========="
    if ! bash "${SCRIPT_DIR}/check_env.sh"; then
        die "Environment check failed. Fix the issues above or re-run with --skip-env-check."
    fi
    info ""
fi

# ================================================================
# Phase 1 — Execute pipeline
# ================================================================
info "========== Phase 1: Execute pipeline =========="
source "${SCRIPT_DIR}/run_execute_pipeline.sh" "${SOURCE_FILE}" \
    ${PROGRAM_ARGS:+--args "${PROGRAM_ARGS}"}

# ================================================================
# Phase 2 — Prove pipeline (optional)
# ================================================================
if [[ "${SKIP_PROVE}" == true ]]; then
    info "Skipping prove pipeline (--skip-prove)."
elif [[ "${CLASSICAL}" == true ]]; then
    info ""
    info "========== Phase 2: Classical prove pipeline (scarb prove + verify) =========="
    export PROGRAM_ID RUN_DIR PKG_DIR PROGRAM_ARGS
    bash "${SCRIPT_DIR}/run_classical_prove_pipeline.sh"
else
    info ""
    info "========== Phase 2: Recursive prove pipeline =========="
    export PROGRAM_ID RUN_DIR PROVER_INPUT
    bash "${SCRIPT_DIR}/run_prove_pipeline.sh"
fi

# ================================================================
# Summary
# ================================================================
info ""
info "========== Summary =========="
info "Program:        ${PROGRAM_ID}"
info "Source:          ${SOURCE_FILE}"
info "Arguments:      ${PROGRAM_ARGS:-<none>}"
info "Run directory:  ${RUN_DIR}"
info ""
info "Artefacts:"
find "${RUN_DIR}" -type f | sort | while read -r f; do
    SIZE="$(du -h "${f}" | cut -f1)"
    echo "  ${SIZE}  ${f#"${RUN_DIR}/"}"
done
