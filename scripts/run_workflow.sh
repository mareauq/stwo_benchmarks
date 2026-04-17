#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_workflow.sh <path/to/program.cairo> [--args "<arguments>"]
#                                         [--skip-recursive]
#
# Top-level entry point:
#   1. Base pipeline  (build → execute → prove → verify)
#   2. Recursive pipeline (convert proof → verifier execute → prove → verify)
#
# Examples:
#   ./scripts/run_workflow.sh programs/fibonacci.cairo --args "10"
#   ./scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --skip-recursive
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- Parse arguments ----
SOURCE_FILE=""
PROGRAM_ARGS=""
SKIP_RECURSIVE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --args) PROGRAM_ARGS="$2"; shift 2 ;;
        --skip-recursive) SKIP_RECURSIVE=true; shift ;;
        *)
            [[ -z "${SOURCE_FILE}" ]] || die "Unexpected argument: $1"
            SOURCE_FILE="$1"; shift ;;
    esac
done
[[ -n "${SOURCE_FILE}" ]] || die "Usage: $0 <path/to/program.cairo> [--args \"...\"] [--skip-recursive]"

# ================================================================
# Phase 1 — Base pipeline
# ================================================================
info "========== Phase 1: Base pipeline =========="

# run_base_pipeline.sh exports PROGRAM_ID, RUN_DIR, PROOF_FILE, EXEC_ID, PKG_DIR
source "${SCRIPT_DIR}/run_base_pipeline.sh" "${SOURCE_FILE}" ${PROGRAM_ARGS:+--args "${PROGRAM_ARGS}"}

# ================================================================
# Phase 2 — Recursive pipeline (optional)
# ================================================================
if [[ "${SKIP_RECURSIVE}" == true ]]; then
    info "Skipping recursive pipeline (--skip-recursive)."
else
    info ""
    info "========== Phase 2: Recursive pipeline =========="
    export PROGRAM_ID RUN_DIR PKG_DIR
    bash "${SCRIPT_DIR}/run_recursive_pipeline.sh"
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
