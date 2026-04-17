#!/usr/bin/env bash
# ---------------------------------------------------------------
# setup_vendor.sh
#
# Clones / updates the pinned version of stwo-cairo into vendor/.
# Only needs to be run once (or when upgrading the pinned version).
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

STWO_CAIRO_VERSION="v1.2.2"
STWO_CAIRO_REPO="https://github.com/starkware-libs/stwo-cairo.git"
VENDOR_DIR="${REPO_ROOT}/vendor/stwo-cairo"

if [[ -d "${VENDOR_DIR}" ]]; then
    info "Vendor directory already exists: ${VENDOR_DIR}"
    CURRENT_TAG="$(cd "${VENDOR_DIR}" && git describe --tags --exact-match 2>/dev/null || echo 'unknown')"
    if [[ "${CURRENT_TAG}" == "${STWO_CAIRO_VERSION}" ]]; then
        info "Already at ${STWO_CAIRO_VERSION}. Nothing to do."
        exit 0
    fi
    info "Current tag: ${CURRENT_TAG}. Updating to ${STWO_CAIRO_VERSION}…"
    (cd "${VENDOR_DIR}" && git fetch --tags && git checkout "${STWO_CAIRO_VERSION}")
else
    info "Cloning stwo-cairo ${STWO_CAIRO_VERSION} into ${VENDOR_DIR}…"
    mkdir -p "$(dirname "${VENDOR_DIR}")"
    git clone --depth 1 --branch "${STWO_CAIRO_VERSION}" \
        "${STWO_CAIRO_REPO}" "${VENDOR_DIR}"
fi

# Quick sanity: verifier workspace must exist
[[ -f "${VENDOR_DIR}/stwo_cairo_verifier/Scarb.toml" ]] \
    || die "Verifier workspace not found after clone."

info "Vendor setup complete: ${VENDOR_DIR} @ ${STWO_CAIRO_VERSION}"
