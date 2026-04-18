#!/usr/bin/env bash
# ---------------------------------------------------------------
# run_prove_pipeline.sh
#
# Phase 2 of the benchmark workflow:
#   Invokes the recursive_prover binary which does:
#   1. Cairo proving     (stwo-cairo prove_cairo)
#   2. Recursive proving (stwo-circuits circuit prover)
#   3. Verification      (stwo-circuits circuit verifier)
#
# Expected environment (set by run_execute_pipeline.sh or caller):
#   PROGRAM_ID    - e.g. "fibonacci"
#   RUN_DIR       - path to the current run artefacts directory
#   PROVER_INPUT  - path to prover_input.json
# ---------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

[[ -n "${PROGRAM_ID:-}" ]]    || die "PROGRAM_ID not set"
[[ -n "${RUN_DIR:-}" ]]       || die "RUN_DIR not set"
[[ -d "${RUN_DIR}" ]]         || die "RUN_DIR does not exist: ${RUN_DIR}"
[[ -n "${PROVER_INPUT:-}" ]]  || PROVER_INPUT="${RUN_DIR}/cairo_vm/prover_input.json"
[[ -f "${PROVER_INPUT}" ]]    || die "prover_input.json not found: ${PROVER_INPUT}"

[[ -x "${RECURSIVE_PROVER_BIN}" ]] \
    || die "recursive_prover binary not found at ${RECURSIVE_PROVER_BIN}. Run: bash scripts/build_prover.sh"

PROOF_FILE="${RUN_DIR}/recursive_proof/proof.json"
VK_FILE="${RUN_DIR}/recursive_proof/vk.json"
BASE_PROOF_FILE="${RUN_DIR}/base_proof/proof.json"

info "Running recursive_prover on ${PROGRAM_ID}…"

"${RECURSIVE_PROVER_BIN}" \
    --input "${PROVER_INPUT}" \
    --output "${PROOF_FILE}" \
    --vk "${VK_FILE}" \
    --base-proof "${BASE_PROOF_FILE}" \
    2>&1 | tee "${RUN_DIR}/logs/prove.log"

[[ -f "${PROOF_FILE}" ]] || die "Proof not produced at ${PROOF_FILE}"
[[ -f "${VK_FILE}" ]]    || die "VK not produced at ${VK_FILE}"

# ---- Extract metrics from proof.json ----
if command -v python3 &>/dev/null && [[ -f "${PROOF_FILE}" ]]; then
    python3 - "${PROOF_FILE}" "${RUN_DIR}/metrics/summary.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    proof = json.load(f)
summary = {
    "cairo_prove_ms": proof.get("cairo_prove_ms"),
    "cairo_proof_bytes": proof.get("cairo_proof_bytes"),
    "recursive_prove_ms": proof.get("recursive_prove_ms"),
    "proof_bytes": proof.get("proof_bytes"),
    "verify_ms": proof.get("verify_ms"),
}
with open(sys.argv[2], "w") as f:
    json.dump(summary, f, indent=2)
PY
    info "Metrics saved to ${RUN_DIR}/metrics/summary.json"
fi

info "Prove pipeline complete."
info "  Base proof bytes:      $(python3 -c "import json; print(json.load(open('${PROOF_FILE}'))['cairo_proof_bytes'])" 2>/dev/null || echo 'N/A')"
info "  Recursive proof bytes: $(python3 -c "import json; print(json.load(open('${PROOF_FILE}'))['proof_bytes'])" 2>/dev/null || echo 'N/A')"

export PROGRAM_ID RUN_DIR PROOF_FILE VK_FILE
