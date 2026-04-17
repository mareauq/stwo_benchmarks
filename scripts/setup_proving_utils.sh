#!/usr/bin/env bash
# ---------------------------------------------------------------
# setup_proving_utils.sh
#
# Installs stwo-run-and-prove from the proving-utils repository.
# This tool can produce proofs in cairo-serde format, which is
# required by the recursive verification pipeline.
#
# Prerequisites: Rust toolchain (cargo) must be installed.
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

PROVING_UTILS_VERSION="1.2.2"

if command -v stwo-run-and-prove &>/dev/null; then
    INSTALLED="$(stwo-run-and-prove --version 2>/dev/null || echo 'unknown')"
    info "stwo-run-and-prove already installed: ${INSTALLED}"
    exit 0
fi

command -v cargo &>/dev/null || die "Rust toolchain (cargo) is required."

info "Installing stwo-run-and-prove ${PROVING_UTILS_VERSION} from crates.io…"
info "This may take several minutes (compiles native code with optimizations)."

RUSTFLAGS="-C target-cpu=native -C opt-level=3" \
    cargo install stwo-run-and-prove --version "${PROVING_UTILS_VERSION}" \
    2>&1 | tail -5

info "stwo-run-and-prove installed successfully."
stwo-run-and-prove --help 2>&1 | head -5
