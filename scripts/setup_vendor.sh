#!/usr/bin/env bash
# ---------------------------------------------------------------
# setup_vendor.sh
#
# Clones stwo-circuits into vendor/stwo-circuits at the pinned
# revision.  Idempotent — skips if already present at the right rev.
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VENDOR_DIR="${REPO_ROOT}/vendor/stwo-circuits"

if [[ -d "${VENDOR_DIR}/.git" ]]; then
    CURRENT="$(cd "${VENDOR_DIR}" && git rev-parse HEAD)"
    if [[ "${STWO_CIRCUITS_REV}" == "main" ]]; then
        info "vendor/stwo-circuits already cloned (${CURRENT:0:8}). Pulling latest main…"
        (cd "${VENDOR_DIR}" && git fetch origin main && git checkout origin/main --detach)
    else
        EXPECTED="$(cd "${VENDOR_DIR}" && git rev-parse "${STWO_CIRCUITS_REV}" 2>/dev/null || echo "")"
        if [[ "${CURRENT}" == "${EXPECTED}" ]]; then
            info "vendor/stwo-circuits already at ${STWO_CIRCUITS_REV} (${CURRENT:0:8}). Skipping."
            exit 0
        fi
        info "Checking out ${STWO_CIRCUITS_REV}…"
        (cd "${VENDOR_DIR}" && git fetch origin && git checkout "${STWO_CIRCUITS_REV}" --detach)
    fi
else
    info "Cloning stwo-circuits into vendor/stwo-circuits…"
    mkdir -p "${REPO_ROOT}/vendor"
    git clone https://github.com/starkware-libs/stwo-circuits.git "${VENDOR_DIR}"
    if [[ "${STWO_CIRCUITS_REV}" != "main" ]]; then
        (cd "${VENDOR_DIR}" && git checkout "${STWO_CIRCUITS_REV}" --detach)
    fi
fi

REV="$(cd "${VENDOR_DIR}" && git rev-parse --short HEAD)"
info "vendor/stwo-circuits ready at ${REV}"
