# Bench STWO — Cairo Recursive Proving Workbench

Flexible structure for benchmarking Cairo programs with the STWO prover,
including a full recursive proof pipeline.

## Quick start

```bash
# 1. One-time: clone the pinned stwo_cairo_verifier
bash scripts/setup_vendor.sh

# 2. Run the base pipeline (execute + prove + verify)
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --skip-recursive

# 3. (optional) Install stwo-run-and-prove for the recursive layer
bash scripts/setup_proving_utils.sh

# 4. Full workflow including recursive proof
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10"
```

## Adding a new benchmark program

1. Write your Cairo source file in `programs/`. It must expose a single
   `#[executable] fn main(...)` entry point with no syscalls.
2. Run the workflow:
   ```bash
   bash scripts/run_workflow.sh programs/my_program.cairo --args "42"
   ```
3. Artefacts appear under `artifacts/programs/my_program/runs/<timestamp>/`.

No other file needs to be edited.

## Repository layout

```
programs/           Cairo source files for benchmarks
scripts/            Automation scripts (see below)
templates/          Scarb package skeleton stamped out per program
vendor/             Pinned upstream dependencies (stwo-cairo v1.2.2)
.generated/         Auto-generated Scarb packages (gitignored)
artifacts/          Persistent artefacts per program/run (gitignored)
PROOF_FORMAT.md     Notes on proof serialization formats
```

## Scripts

| Script                     | Purpose |
|----------------------------|---------|
| `setup_vendor.sh`          | Clone `stwo-cairo` at the pinned version |
| `setup_proving_utils.sh`   | Install `stwo-run-and-prove` from crates.io |
| `prepare_program.sh`       | Generate a Scarb package wrapping a `.cairo` file |
| `run_base_pipeline.sh`     | Build, execute, prove, verify (base layer) |
| `run_recursive_pipeline.sh`| Recursive verification layer |
| `run_workflow.sh`          | Facade: base + recursive pipelines |
| `common.sh`                | Shared functions and constants |

## Artefact structure (per run)

```
artifacts/programs/<program_id>/runs/<timestamp>/
  compiled/         Scarb.toml + executable JSON
  inputs/           Program arguments
  outputs/          (reserved for program output files)
  vm/               Prover input / execution traces
  base_proof/       proof.json from scarb prove
  recursive_proof/  cairo-serde proof + recursive proof
  logs/             Stdout/stderr of each pipeline step
```

## Requirements

- **scarb** nightly (2.17+) with `scarb-execute`, `scarb-prove`, `scarb-verify`
- **Rust toolchain** (for `stwo-run-and-prove`, recursive layer only)
- Linux x86_64 (STWO prover not available on Windows)
