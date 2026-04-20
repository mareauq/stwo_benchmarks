#!/usr/bin/env bash
# ---------------------------------------------------------------
# check_env.sh [--strict]
#
# Verifies that all the tools required by the pipeline are present
# and at the expected versions.
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

STRICT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict) STRICT=true; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done

FAIL_COUNT=0
WARN_COUNT=0

ok()   { printf "  \033[32m[OK]\033[0m   %s\n" "$*"; }
ko()   { printf "  \033[31m[FAIL]\033[0m %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
soft() { printf "  \033[33m[WARN]\033[0m %s\n" "$*"; WARN_COUNT=$((WARN_COUNT+1)); }

echo "=== Environment check ==="
echo "Expected versions:"
echo "  Rust nightly          ${RUST_NIGHTLY}"
echo "  scarb                 ${SCARB_VERSION}"
echo "  cairo_execute         ${CAIRO_EXECUTE_VERSION}"
echo "  stwo-circuits         ${STWO_CIRCUITS_REV:0:8}"
echo "  recursive_prover      ${RECURSIVE_PROVER_BIN}"
echo ""

# ---- scarb ----
echo "[Cairo toolchain]"
if ! command -v scarb &>/dev/null; then
    ko "scarb not found on PATH"
else
    SCARB_V="$(scarb --version 2>/dev/null | head -n1 | awk '{print $2}')"
    ok "scarb present (${SCARB_V})"
fi

if command -v asdf &>/dev/null; then
    if asdf list scarb 2>/dev/null | grep -qF "${SCARB_VERSION}"; then
        ok "scarb ${SCARB_VERSION} installed via asdf"
    else
        ko "scarb ${SCARB_VERSION} not installed (asdf install scarb ${SCARB_VERSION})"
    fi
else
    soft "asdf not found — cannot verify scarb ${SCARB_VERSION}"
fi

for sub in scarb-execute; do
    if command -v "${sub}" &>/dev/null; then
        ok "${sub} present"
    else
        ko "${sub} not found on PATH"
    fi
done

# ---- Rust nightly ----
echo ""
echo "[Rust toolchain]"
if command -v rustup &>/dev/null; then
    if rustup toolchain list 2>/dev/null | grep -q "${RUST_NIGHTLY}"; then
        ok "Rust ${RUST_NIGHTLY} installed"
    else
        ko "Rust ${RUST_NIGHTLY} not installed (rustup toolchain install ${RUST_NIGHTLY})"
    fi
else
    ko "rustup not found"
fi

# ---- vendor ----
echo ""
echo "[Vendored dependencies]"
VENDOR_DIR="${REPO_ROOT}/vendor/stwo-circuits"
if [[ -d "${VENDOR_DIR}" ]]; then
    REV="$(cd "${VENDOR_DIR}" && git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    if [[ "${REV}" == "${STWO_CIRCUITS_REV}" ]]; then
        ok "vendor/stwo-circuits present (${REV:0:8})"
    else
        ko "vendor/stwo-circuits at ${REV:0:8}, expected ${STWO_CIRCUITS_REV:0:8} (run scripts/setup_vendor.sh)"
    fi
else
    ko "vendor/stwo-circuits missing (run scripts/setup_vendor.sh)"
fi

# ---- recursive_prover binary ----
echo ""
echo "[Prover binary]"
if [[ -x "${RECURSIVE_PROVER_BIN}" ]]; then
    ok "recursive_prover available at ${RECURSIVE_PROVER_BIN}"
else
    ko "recursive_prover not built (run scripts/build_prover.sh)"
fi

echo ""
echo "=== Summary: ${FAIL_COUNT} failure(s), ${WARN_COUNT} warning(s) ==="

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    exit 1
fi
if [[ "${STRICT}" == true && ${WARN_COUNT} -gt 0 ]]; then
    exit 1
fi
exit 0
