"""Configuration du backend.

Ce backend vit dans `stwo_benchmarks/webapp/backend/app/`. Par défaut,
il déduit la racine du dépôt bench à partir de son propre chemin, ce qui
évite toute variable d'environnement dans le cas nominal (le dépôt est
autonome).

La variable `STWO_BENCHMARKS_DIR` reste honorée si quelqu'un veut pointer
le backend vers un autre clone ou une version alternative du bench.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


# backend/app/config.py → backend/app → backend → webapp → <bench root>
_MODULE = Path(__file__).resolve()
DEFAULT_BENCH_DIR = _MODULE.parents[3]


@dataclass(frozen=True)
class Settings:
    bench_dir: Path
    default_mode: str
    proof_preview_bytes: int
    allow_arbitrary_program_id: bool

    @property
    def run_workflow_script(self) -> Path:
        return self.bench_dir / "scripts" / "run_workflow.sh"

    @property
    def programs_dir(self) -> Path:
        return self.bench_dir / "programs"

    @property
    def artifacts_dir(self) -> Path:
        return self.bench_dir / "artifacts" / "programs"


def load_settings() -> Settings:
    bench_dir = Path(
        os.environ.get("STWO_BENCHMARKS_DIR", str(DEFAULT_BENCH_DIR))
    ).expanduser().resolve()

    default_mode = os.environ.get("STARK_WEBAPP_DEFAULT_MODE", "classical").lower()
    if default_mode not in {"execute", "classical", "recursive"}:
        default_mode = "classical"

    try:
        preview = int(os.environ.get("STARK_WEBAPP_PROOF_PREVIEW_BYTES", "65536"))
    except ValueError:
        preview = 65536

    allow_arbitrary = os.environ.get("STARK_WEBAPP_ALLOW_ARBITRARY_ID", "0") == "1"

    return Settings(
        bench_dir=bench_dir,
        default_mode=default_mode,
        proof_preview_bytes=max(1024, preview),
        allow_arbitrary_program_id=allow_arbitrary,
    )


SETTINGS = load_settings()
