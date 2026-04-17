# Proof Format Compatibility

## The problem

The recursive pipeline requires feeding a proof from the base layer into the
`stwo_cairo_verifier` program. These two components speak different serialization
formats:

| Producer              | Output format        | File example       |
|-----------------------|----------------------|--------------------|
| `scarb prove`         | Structured JSON      | `proof.json`       |
| `stwo-run-and-prove`  | Cairo-serde (flat felt array, default) | `proof.cairo_serde.json` |

The `stwo_cairo_verifier` is a Cairo program invoked via
`scarb execute --arguments-file <file>`. The `--arguments-file` flag expects a
**JSON array of hex-encoded felt252 values** (Cairo Serde format), not the
structured JSON that `scarb prove` emits.

## Why a direct conversion is non-trivial

The structured JSON proof contains nested objects, arrays of tuples, and
field-specific encodings (M31, CM31, QM31). Flattening this into a felt array
requires the exact same traversal order as the `CairoSerialize` derive macro
from the `stwo-cairo-serialize` Rust crate. A hand-written converter would be
fragile and break on every upstream version bump.

## Recommended approach

Use `stwo-run-and-prove` (from `proving-utils`) to **re-run and re-prove** the
user program with `--proof-format cairo-serde`. This produces the exact format
the verifier expects, without any post-hoc conversion.

```
stwo-run-and-prove \
    --program <compiled_program.json> \
    --proof_path <output.cairo_serde.json> \
    --proof-format cairo-serde \
    --verify
```

Install it via:
```
bash scripts/setup_proving_utils.sh
```

## Alternative: pre-place the serde proof

If you have access to another tool that produces the cairo-serde proof, or if
you already have a `proof.cairo_serde.json` file, place it at:
```
artifacts/programs/<program_id>/runs/<run_id>/recursive_proof/proof.cairo_serde.json
```
The recursive pipeline will detect and use it automatically.

## Current status (v1.2.2)

- `scarb prove` does **not** support `--proof-format`.
- `stwo-run-and-prove` defaults to `cairo-serde` format.
- The vendored verifier (`v1.2.2`) is confirmed to build with scarb nightly
  and the `qm31_opcode` feature flag.
- End-to-end recursive proving depends on `stwo-run-and-prove` being installed.
