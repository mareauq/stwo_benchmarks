#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROGRAMS_DIR="${REPO_ROOT}/programs"
TEMPLATES_DIR="${REPO_ROOT}/templates"
GENERATED_DIR="${REPO_ROOT}/.generated/programs"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/programs"

log()  { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }
info() { log "$*"; }

# Derive a stable program id from a .cairo source path.
# e.g. programs/fibonacci.cairo -> fibonacci
program_id_from_source() {
    local src="$1"
    basename "${src}" .cairo
}

# Resolve the generated Scarb package directory for a given program id.
gen_pkg_dir() {
    echo "${GENERATED_DIR}/$1/app"
}

# Create a timestamped run directory under artifacts/<program_id>/runs/.
# Prints the created path to stdout.
create_run_dir() {
    local program_id="$1"
    local run_id
    run_id="$(date +%Y%m%d_%H%M%S)"
    local run_dir="${ARTIFACTS_DIR}/${program_id}/runs/${run_id}"
    mkdir -p "${run_dir}"/{compiled,inputs,outputs,vm,base_proof,recursive_proof,logs}
    echo "${run_dir}"
}

# Copy a section of build / execution artifacts into the run directory.
copy_if_exists() {
    local src="$1" dst="$2"
    if [[ -e "${src}" ]]; then
        cp -r "${src}" "${dst}"
    fi
}

# The vendored stwo_cairo_verifier is pinned to an older scarb version.
# Override via ASDF_SCARB_VERSION so asdf picks the locally installed nightly.
SCARB_VERSION_FOR_VERIFIER="${SCARB_VERSION_FOR_VERIFIER:-nightly-2026-04-15}"
export ASDF_SCARB_VERSION_FOR_VERIFIER="${SCARB_VERSION_FOR_VERIFIER}"

# Run scarb in the verifier workspace with the correct version override.
scarb_verifier() {
    ASDF_SCARB_VERSION="${SCARB_VERSION_FOR_VERIFIER}" scarb "$@"
}
