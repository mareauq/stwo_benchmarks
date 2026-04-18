#!/usr/bin/env bash
# ---------------------------------------------------------------
# build_prover.sh
#
# Compiles crates/recursive_prover in release mode and installs
# the binary to .tools/bin/recursive_prover.
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

PROVER_CRATE="${REPO_ROOT}/crates/recursive_prover"
[[ -f "${PROVER_CRATE}/Cargo.toml" ]] || die "Crate not found: ${PROVER_CRATE}"

# Ensure the vendored stwo-circuits is present (path deps need it).
VENDOR_DIR="${REPO_ROOT}/vendor/stwo-circuits"
[[ -d "${VENDOR_DIR}" ]] || die "vendor/stwo-circuits not found. Run: bash scripts/setup_vendor.sh"

info "Building recursive_prover (release) with Rust ${RUST_NIGHTLY}…"
(cd "${PROVER_CRATE}" && cargo "+${RUST_NIGHTLY}" build --release) \
    || die "cargo build failed"

mkdir -p "${TOOLS_BIN_DIR}"
cp "${PROVER_CRATE}/target/release/recursive_prover" "${RECURSIVE_PROVER_BIN}"
chmod +x "${RECURSIVE_PROVER_BIN}"

info "Installed: ${RECURSIVE_PROVER_BIN}"
