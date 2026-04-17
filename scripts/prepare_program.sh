#!/usr/bin/env bash
# ---------------------------------------------------------------
# prepare_program.sh <path/to/program.cairo>
#
# Generates a self-contained Scarb package under .generated/
# that wraps the supplied Cairo source so it can be built,
# executed and proved with the standard scarb toolchain.
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

[[ $# -ge 1 ]] || die "Usage: $0 <path/to/program.cairo>"

SOURCE_FILE="$(realpath "$1")"
[[ -f "${SOURCE_FILE}" ]] || die "Source file not found: ${SOURCE_FILE}"

PROGRAM_ID="$(program_id_from_source "${SOURCE_FILE}")"
PKG_DIR="$(gen_pkg_dir "${PROGRAM_ID}")"

info "Preparing package for '${PROGRAM_ID}' in ${PKG_DIR}"

rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/src"

# Stamp out Scarb.toml from template
sed "s/{{PROGRAM_ID}}/${PROGRAM_ID}/g" \
    "${TEMPLATES_DIR}/Scarb.toml.tpl" > "${PKG_DIR}/Scarb.toml"

# Stable lib.cairo wrapper
cp "${TEMPLATES_DIR}/lib.cairo.tpl" "${PKG_DIR}/src/lib.cairo"

# Inject the user source as the canonical module
cp "${SOURCE_FILE}" "${PKG_DIR}/src/program.cairo"

# Quick build check
info "Building package…"
(cd "${PKG_DIR}" && scarb build) || die "Build failed for ${PROGRAM_ID}"

info "Package ready: ${PKG_DIR}"
