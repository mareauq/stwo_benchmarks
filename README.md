# STWO Benchmarks — Recursive Cairo Proving Workbench

Flexible structure for benchmarking **Cairo 1** programs with the STWO prover,
including a full recursive proof pipeline via `stwo-circuits`.

## Architecture

This project uses the **hackx-zkcs** approach for recursive proving, which
differs from the Cairo 0 pipeline described in `CONTEXT.md` (lessons from the
prior `Bench_stwo` attempt). Key differences:

| Aspect | CONTEXT.md (Bench_stwo) | This project |
|--------|------------------------|--------------|
| Cairo version | Cairo 0 (`%builtins …`) | **Cairo 1** (`#[executable]`) |
| Compilation | `cairo-compile` (Python) | `scarb build` / `scarb execute` |
| Base prover input | `run_and_prove` on `compiled.json` | `scarb execute --target bootloader` → `prover_input.json` |
| Base proving | `stwo-run-and-prove` (crates.io) | `prove_cairo` via Rust driver |
| Recursion engine | `stwo_cairo_verifier` (Cairo program) + `scarb prove/verify` | **`stwo-circuits`** (Rust arithmetic circuit prover) |
| Recursion driver | Scarb toolchain | Custom `recursive_prover` binary |

The `stwo-circuits` approach bypasses the `stwo_cairo_verifier` Cairo program
entirely, avoiding the `n_builtins == 11` limitation that blocked Cairo 1
recursion in the prior attempt (see `CONTEXT.md` §6.2).

## Quick start

```bash
# 1. Clone the vendored stwo-circuits
bash scripts/setup_vendor.sh

# 2. Build the recursive prover binary (requires Rust nightly-2025-06-23)
bash scripts/build_prover.sh

# 3. Check your environment
bash scripts/check_env.sh

# 4. Execute-only (no proving)
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --skip-prove

# 5. Classical proof (scarb prove + verify, no recursion)
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --classical

# 6. Full workflow: execute + base proof + recursive proof + verify
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10"
```

## Classical proving (without recursion)

Use the `--classical` flag for a standard STARK proof (via `scarb prove` /
`scarb verify`) without the recursive circuit layer:

```bash
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --classical
```

This runs the same execute + prove + verify pipeline, but uses `scarb prove`
(standalone target) instead of the `recursive_prover` binary. No Rust build or
`stwo-circuits` vendor needed.

Use `--skip-prove` if you only need execution (no proof at all):

```bash
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --skip-prove
```

## Adding a new benchmark program

1. Write your Cairo 1 source file in `programs/`. It must expose a single
   `#[executable] fn main(...)` entry point with no syscalls.
2. Run the workflow:
   ```bash
   bash scripts/run_workflow.sh programs/my_program.cairo --args "42"
   ```
3. Artefacts appear under `artifacts/programs/my_program/runs/<timestamp>/`.

No other file needs to be edited.

## Repository layout

```
programs/                Cairo source files for benchmarks
scripts/                 Automation scripts (see below)
templates/               Scarb package skeleton stamped out per program
crates/recursive_prover/ Rust binary: base proof + recursive proof + verify
vendor/                  Vendored stwo-circuits (gitignored)
.generated/              Auto-generated Scarb packages (gitignored)
.tools/                  Compiled recursive_prover binary (gitignored)
artifacts/               Persistent artefacts per program/run (gitignored)
docs/                    Reference documentation (ecosystem, proof formats)
CONTEXT.md               Lessons learned from prior attempt (Bench_stwo)
```

## Scripts

| Script                     | Purpose |
|----------------------------|---------|
| `setup_vendor.sh`          | Clone `stwo-circuits` at the pinned revision |
| `build_prover.sh`          | Build `recursive_prover` from `crates/recursive_prover/` |
| `prepare_program.sh`       | Generate a Scarb package wrapping a `.cairo` file |
| `run_execute_pipeline.sh`  | `scarb execute` → prover_input.json (bootloader) or execution output (standalone) |
| `run_prove_pipeline.sh`    | `recursive_prover` → base proof + recursive proof + verify |
| `run_classical_prove_pipeline.sh` | `scarb prove` + `scarb verify` (no recursion) |
| `run_workflow.sh`          | Facade: execute + prove pipelines (`--classical` for non-recursive) |
| `check_env.sh`             | Verify that installed toolchains match expected versions |
| `common.sh`                | Shared functions and **pinned versions** (single source of truth) |

## Artefact structure (per run)

```
artifacts/programs/<program_id>/runs/<timestamp>/
  compiled/         Scarb.toml + source + executable JSON
  inputs/           Program arguments
  outputs/          Program output (program_output.txt)
  cairo_vm/         prover_input.json + VM artifacts
  base_proof/       (reserved for base proof export)
  recursive_proof/  proof.json + vk.json
  logs/             Stdout/stderr of each pipeline step
  metrics/          summary.json with timings and sizes
```

## Pipeline overview

```
programs/foo.cairo                          Cairo 1 source (#[executable])
    │  prepare_program.sh
    ▼
.generated/programs/foo/app/                Scarb package (auto-generated)
    │  scarb execute --target bootloader --output standard
    ▼
prover_input.json                           CairoVM trace + public inputs
    │  recursive_prover (phase 1: stwo-cairo prove_cairo)
    ▼
CairoProof<Blake2s> (in memory)             Base STARK proof (~1 MB)
    │  recursive_prover (phase 2: stwo-circuits)
    │    - build_fixed_cairo_circuit → QM31 verifier circuit
    │    - PreprocessedCircuit::preprocess_circuit (finalize + pad)
    │    - prove_circuit_assignment → CircuitProof
    ▼
proof.json + vk.json                        Recursive proof (~60 KB)
    │  recursive_prover (phase 3: verify_circuit)
    ▼
OK
```

The recursive prover uses a **single QM31 context** for both preprocessing and
proving — the same context is finalized by `preprocess_circuit`, then its values
are passed to `prove_circuit_assignment`. This matches the pattern used in
`stwo-circuits` tests.

## Dependency pins

All version pins live in `scripts/common.sh` and
`crates/recursive_prover/Cargo.toml`. Current defaults:

| Component              | Version / revision           |
|------------------------|------------------------------|
| `stwo`                 | 2.2.0 (crates.io)           |
| `stwo-cairo`           | git rev `0a5e70b7`          |
| `stwo-circuits`        | vendored (main branch)      |
| Rust nightly           | `nightly-2025-06-23`        |
| `scarb`                | `nightly-2026-04-15` (asdf) |
| `cairo_execute` (Scarb)| 2.17.0                       |

## Benchmark results (fibonacci, n=10)

| Metric | Value |
|--------|-------|
| Cairo steps | 5 756 |
| Base proof (stwo-cairo) | ~7s, ~1 MB |
| Recursive proof (stwo-circuits) | ~19s, ~61 KB |
| Verification | ~180ms |

## Reference

- `docs/ecosystem.md` — Full STWO/Cairo ecosystem reference.
- `CONTEXT.md` — Lessons learned from the prior attempt (Bench_stwo, Cairo 0).
  Section 11 explains why this project diverged to a Cairo 1 + stwo-circuits
  approach.
