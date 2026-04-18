#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROGRAMS_DIR="${REPO_ROOT}/programs"
TEMPLATES_DIR="${REPO_ROOT}/templates"
GENERATED_DIR="${REPO_ROOT}/.generated/programs"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/programs"

# ================================================================
# Pinned versions — single source of truth
# ================================================================

# stwo-circuits tag or commit used by setup_vendor.sh.
STWO_CIRCUITS_REV="${STWO_CIRCUITS_REV:-main}"

# Rust nightly required by stwo-circuits and the recursive prover.
RUST_NIGHTLY="${RUST_NIGHTLY:-nightly-2025-06-23}"

# Local install prefix for the recursive prover binary.
TOOLS_DIR="${TOOLS_DIR:-${REPO_ROOT}/.tools}"
TOOLS_BIN_DIR="${TOOLS_BIN_DIR:-${TOOLS_DIR}/bin}"

# Path to the recursive prover binary built from crates/recursive_prover.
RECURSIVE_PROVER_BIN="${RECURSIVE_PROVER_BIN:-${TOOLS_BIN_DIR}/recursive_prover}"

# Scarb version for building/executing user programs.
# Must produce prover_input.json compatible with the stwo-cairo rev
# pinned in crates/recursive_prover/Cargo.toml.
SCARB_VERSION="${SCARB_VERSION:-nightly-2026-04-15}"

# cairo_execute crate version used inside Scarb.toml templates.
CAIRO_EXECUTE_VERSION="${CAIRO_EXECUTE_VERSION:-2.17.0}"

# ================================================================
# Logging helpers
# ================================================================
log()  { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }
info() { log "$*"; }
warn() { log "WARN: $*" >&2; }

# ================================================================
# Path helpers
# ================================================================

program_id_from_source() {
    local src="$1"
    basename "${src}" .cairo
}

gen_pkg_dir() {
    echo "${GENERATED_DIR}/$1/app"
}

create_run_dir() {
    local program_id="$1"
    local run_id
    run_id="$(date +%Y%m%d_%H%M%S)"
    local run_dir="${ARTIFACTS_DIR}/${program_id}/runs/${run_id}"
    mkdir -p "${run_dir}"/{compiled,inputs,outputs,cairo_vm,base_proof,recursive_proof,logs,metrics}
    echo "${run_dir}"
}

copy_if_exists() {
    local src="$1" dst="$2"
    if [[ -e "${src}" ]]; then
        cp -r "${src}" "${dst}"
    fi
}

# ================================================================
# Toolchain helpers
# ================================================================

scarb_run() {
    ASDF_SCARB_VERSION="${SCARB_VERSION}" scarb "$@"
}
