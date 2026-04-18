#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_execute_pipeline.sh <path/to/program.cairo> [--args "<arguments>"]
#                                                  [--target bootloader|standalone]
#
# Phase 1 of the benchmark workflow:
#   1. Prepare Scarb package from .cairo source (idempotent).
#   2. scarb execute --target <target> --output standard
#
# --target bootloader  (default) produces prover_input.json for recursive_prover
# --target standalone  produces execution output for scarb prove / scarb verify
#
# Exports: PROGRAM_ID, RUN_DIR, PKG_DIR, PROVER_INPUT, EXEC_TARGET
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SOURCE_FILE=""
PROGRAM_ARGS=""
EXEC_TARGET="bootloader"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --args)   PROGRAM_ARGS="$2"; shift 2 ;;
        --target) EXEC_TARGET="$2"; shift 2 ;;
        *)
            [[ -z "${SOURCE_FILE}" ]] || die "Unexpected argument: $1"
            SOURCE_FILE="$1"; shift ;;
    esac
done
[[ -n "${SOURCE_FILE}" ]] || die "Usage: $0 <path/to/program.cairo> [--args \"<arguments>\"] [--target bootloader|standalone]"

SOURCE_FILE="$(realpath "${SOURCE_FILE}")"
PROGRAM_ID="$(program_id_from_source "${SOURCE_FILE}")"
PKG_DIR="$(gen_pkg_dir "${PROGRAM_ID}")"

# ---- Prepare package ----
bash "${SCRIPT_DIR}/prepare_program.sh" "${SOURCE_FILE}"

# ---- Create run directory ----
RUN_DIR="$(create_run_dir "${PROGRAM_ID}")"
info "Run directory: ${RUN_DIR}"

# ---- Archive compiled artifacts ----
EXECUTABLE_JSON="${PKG_DIR}/target/dev/${PROGRAM_ID}.executable.json"
[[ -f "${EXECUTABLE_JSON}" ]] || die "Executable not produced: ${EXECUTABLE_JSON}"
cp "${EXECUTABLE_JSON}" "${RUN_DIR}/compiled/${PROGRAM_ID}.executable.json"
cp "${PKG_DIR}/Scarb.toml" "${RUN_DIR}/compiled/Scarb.toml"
cp "${PKG_DIR}/src/program.cairo" "${RUN_DIR}/compiled/program.cairo"

# ---- Save arguments ----
if [[ -n "${PROGRAM_ARGS}" ]]; then
    echo "${PROGRAM_ARGS}" > "${RUN_DIR}/inputs/arguments.txt"
else
    echo "(no arguments)" > "${RUN_DIR}/inputs/arguments.txt"
fi

# ---- Execute ----
info "Executing ${PROGRAM_ID} with scarb execute (${EXEC_TARGET} target)…"

EXEC_ARGS=(execute --target "${EXEC_TARGET}" --output standard)
[[ -n "${PROGRAM_ARGS}" ]] && EXEC_ARGS+=(--arguments "${PROGRAM_ARGS}")
EXEC_ARGS+=(--print-program-output --print-resource-usage)

(cd "${PKG_DIR}" && scarb_run "${EXEC_ARGS[@]}") \
    2>&1 | tee "${RUN_DIR}/logs/execute.log"

# ---- Locate prover_input.json (bootloader only) ----
PROVER_INPUT=""
if [[ "${EXEC_TARGET}" == "bootloader" ]]; then
    EXEC_BASE="${PKG_DIR}/target/execute/${PROGRAM_ID}"
    LATEST_EXEC="$(ls -1d "${EXEC_BASE}"/execution* 2>/dev/null | sort -V | tail -n1)" \
        || die "No execution output found under ${EXEC_BASE}"

    PROVER_INPUT="${LATEST_EXEC}/prover_input.json"
    [[ -f "${PROVER_INPUT}" ]] || die "prover_input.json not produced at ${PROVER_INPUT}"

    cp "${PROVER_INPUT}" "${RUN_DIR}/cairo_vm/prover_input.json"
    info "prover_input.json saved ($(du -h "${RUN_DIR}/cairo_vm/prover_input.json" | cut -f1))"
fi

# ---- Extract program output from execute log ----
if [[ -f "${RUN_DIR}/logs/execute.log" ]]; then
    sed -n '/^Program output:$/,/^Resources:$/{/^Program output:$/d;/^Resources:$/d;p}' \
        "${RUN_DIR}/logs/execute.log" > "${RUN_DIR}/outputs/program_output.txt"
    info "Program output saved to ${RUN_DIR}/outputs/program_output.txt"
fi

info "Execute pipeline complete. Artefacts in ${RUN_DIR}"

export PROGRAM_ID RUN_DIR PKG_DIR PROVER_INPUT EXEC_TARGET
