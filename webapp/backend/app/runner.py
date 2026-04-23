"""Orchestration du pipeline `run_workflow.sh`.

Cette couche est isolée de FastAPI pour rester testable : elle ne fait que
(1) écrire la source Cairo dans le repo `stwo_benchmarks`,
(2) lancer le script bash correspondant au mode demandé,
(3) lire les artefacts depuis le dernier `run_dir`.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .config import SETTINGS
from .schemas import ProofArtifact, ProvingMode, RunRequest, RunResult, RunSummary


PROGRAM_ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
RUN_TIMESTAMP_RE = re.compile(r"^[0-9_]{8,32}$")


class RunnerError(RuntimeError):
    """Erreur fonctionnelle du pipeline (source invalide, bench manquant, …)."""


@dataclass
class PipelineOutcome:
    returncode: int
    stdout: str
    stderr: str
    run_dir: Optional[Path]


def validate_program_id(program_id: str) -> str:
    """Autorise un identifiant court et sûr pour créer un fichier.cairo.

    On veut éviter les path traversals et conflits avec les programmes
    préchargés de `stwo_benchmarks`. Le frontend envoie `playground` par
    défaut ; les autres valeurs doivent matcher une regex stricte.
    """
    pid = (program_id or "").strip().lower()
    if not PROGRAM_ID_RE.match(pid):
        raise RunnerError(
            "program_id invalide (attendu: [a-z][a-z0-9_]{0,31})"
        )
    return pid


def _write_program_source(program_id: str, source_code: str) -> Path:
    dst = SETTINGS.programs_dir / f"{program_id}.cairo"
    SETTINGS.programs_dir.mkdir(parents=True, exist_ok=True)
    dst.write_text(source_code, encoding="utf-8")
    return dst


def _latest_run_dir(program_id: str) -> Optional[Path]:
    runs_root = SETTINGS.artifacts_dir / program_id / "runs"
    if not runs_root.is_dir():
        return None
    candidates = sorted(
        (p for p in runs_root.iterdir() if p.is_dir()),
        key=lambda p: p.name,
    )
    return candidates[-1] if candidates else None


def _read_text_if_exists(path: Path, max_bytes: int = 1_000_000) -> Optional[str]:
    if not path.is_file():
        return None
    data = path.read_bytes()[:max_bytes]
    return data.decode("utf-8", errors="replace")


def _read_json_if_exists(path: Path) -> Optional[dict]:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def _collect_logs(run_dir: Path) -> Optional[str]:
    logs_dir = run_dir / "logs"
    if not logs_dir.is_dir():
        return None
    parts: list[str] = []
    for log in sorted(logs_dir.glob("*.log")):
        parts.append(f"===== {log.name} =====")
        text = _read_text_if_exists(log, max_bytes=200_000)
        if text is not None:
            parts.append(text)
    return "\n".join(parts) if parts else None


def _build_proof_artifact(run_dir: Path, mode: ProvingMode) -> ProofArtifact:
    if mode == "execute":
        return ProofArtifact(kind="none")

    if mode == "recursive":
        return _build_recursive_proof_artifact(run_dir)
    return _build_classical_proof_artifact(run_dir)


def _build_recursive_proof_artifact(run_dir: Path) -> ProofArtifact:
    """Extrait directement `proof_hex` + `proof_bytes` du JSON recursive.

    Le binaire `recursive_prover` écrit une structure connue :
        { proof_hex, cairo_prove_ms, cairo_proof_bytes,
          recursive_prove_ms, proof_bytes, verify_ms }
    La "taille brute" de la preuve est `proof_bytes` (ou, à défaut,
    `len(proof_hex) / 2`). Elle est strictement plus petite que la taille du
    fichier JSON sur disque, qui inclut l'encodage hex + les métadonnées.
    """
    candidate = run_dir / "recursive_proof" / "proof.json"
    if not candidate.is_file():
        return ProofArtifact(kind="none")

    size = candidate.stat().st_size
    data = _read_json_if_exists(candidate)
    raw_hex: Optional[str] = None
    raw_bytes: Optional[int] = None
    if isinstance(data, dict):
        proof_hex = data.get("proof_hex")
        if isinstance(proof_hex, str):
            raw_hex = proof_hex
            reported = data.get("proof_bytes")
            if isinstance(reported, int) and reported > 0:
                raw_bytes = reported
            else:
                raw_bytes = len(proof_hex) // 2

    return ProofArtifact(
        kind="recursive",
        path=str(candidate),
        size_bytes=size,
        raw_hex=raw_hex,
        raw_bytes=raw_bytes,
    )


def _build_classical_proof_artifact(run_dir: Path) -> ProofArtifact:
    candidate = _find_first_json(run_dir / "base_proof") or _find_first_json(
        run_dir / "recursive_proof"
    )
    if not candidate or not candidate.is_file():
        return ProofArtifact(kind="none")

    size = candidate.stat().st_size
    limit = SETTINGS.proof_preview_bytes
    raw = candidate.read_bytes()[:limit]
    preview = raw.decode("utf-8", errors="replace")
    truncated = size > limit

    return ProofArtifact(
        kind="classical",
        path=str(candidate),
        size_bytes=size,
        preview=preview,
        truncated=truncated,
    )


def _find_first_json(directory: Path) -> Optional[Path]:
    if not directory.is_dir():
        return None
    matches = sorted(directory.glob("*.json"))
    return matches[0] if matches else None


def _mode_flags(mode: ProvingMode) -> list[str]:
    if mode == "execute":
        return ["--skip-prove"]
    if mode == "classical":
        return ["--classical"]
    return []  # recursive est le défaut du workflow


def run_pipeline(req: RunRequest) -> RunResult:
    started = time.monotonic()

    if not SETTINGS.run_workflow_script.is_file():
        raise RunnerError(
            f"Script introuvable: {SETTINGS.run_workflow_script}. "
            "Vérifier STWO_BENCHMARKS_DIR."
        )

    program_id = validate_program_id(req.program_id)
    mode: ProvingMode = req.mode or SETTINGS.default_mode  # type: ignore[assignment]

    source_path = _write_program_source(program_id, req.source_code)

    cmd: list[str] = [
        "bash",
        str(SETTINGS.run_workflow_script),
        str(source_path),
    ]
    if req.args.strip():
        cmd += ["--args", req.args.strip()]
    cmd += _mode_flags(mode)
    if req.skip_env_check:
        cmd += ["--skip-env-check"]

    proc = subprocess.run(
        cmd,
        cwd=str(SETTINGS.bench_dir),
        capture_output=True,
        text=True,
        check=False,
    )

    run_dir = _latest_run_dir(program_id)
    duration_ms = int((time.monotonic() - started) * 1000)

    if proc.returncode != 0:
        logs = proc.stdout + "\n" + proc.stderr
        return RunResult(
            status="error",
            mode=mode,
            program_id=program_id,
            run_dir=str(run_dir) if run_dir else None,
            duration_ms=duration_ms,
            logs=logs[-20_000:],
            error=_extract_error_hint(logs),
        )

    return collect_run_result(
        program_id=program_id,
        run_dir=run_dir,
        mode=mode,
        duration_ms=duration_ms,
        fallback_logs=proc.stdout + ("\n" + proc.stderr if proc.stderr else ""),
    )


def collect_run_result(
    program_id: str,
    run_dir: Optional[Path],
    mode: ProvingMode,
    duration_ms: int,
    fallback_logs: str = "",
) -> RunResult:
    """Assemble un RunResult à partir d'un `run_dir` déjà existant.

    Utilisé à la fois après un run (via run_pipeline) et lors du rechargement
    d'un run passé via l'API `/api/runs/{timestamp}`.
    """
    program_output: Optional[str] = None
    metrics: Optional[dict] = None
    proof = ProofArtifact(kind="none")
    logs: Optional[str] = fallback_logs or None

    if run_dir is not None:
        program_output = _read_text_if_exists(run_dir / "outputs" / "program_output.txt")
        metrics = _read_json_if_exists(run_dir / "metrics" / "summary.json")
        proof = _build_proof_artifact(run_dir, mode)
        run_logs = _collect_logs(run_dir)
        if run_logs:
            logs = run_logs

    return RunResult(
        status="success",
        mode=mode,
        program_id=program_id,
        run_dir=str(run_dir) if run_dir else None,
        duration_ms=duration_ms,
        program_output=program_output,
        proof=proof,
        logs=logs[-40_000:] if logs else None,
        metrics=metrics,
    )


def _detect_mode(run_dir: Path) -> ProvingMode:
    """Devine le mode d'un run passé à partir des artefacts présents.

    - recursive: il y a une proof.json dans `recursive_proof/` avec `proof_hex`.
    - classical: il y a un JSON dans `base_proof/` mais pas de proof récursive.
    - execute:   rien de tout ça, seulement l'exécution Cairo.
    """
    recursive = run_dir / "recursive_proof" / "proof.json"
    if recursive.is_file():
        data = _read_json_if_exists(recursive)
        if isinstance(data, dict) and isinstance(data.get("proof_hex"), str):
            return "recursive"
    if _find_first_json(run_dir / "base_proof") is not None:
        return "classical"
    return "execute"


def _run_dir_for(program_id: str, timestamp: str) -> Optional[Path]:
    if not RUN_TIMESTAMP_RE.match(timestamp):
        return None
    candidate = SETTINGS.artifacts_dir / program_id / "runs" / timestamp
    if not candidate.is_dir():
        return None
    try:
        candidate.resolve().relative_to(SETTINGS.artifacts_dir.resolve())
    except ValueError:
        return None
    return candidate


def list_runs(program_id: str) -> list[RunSummary]:
    """Liste les runs stockés pour un `program_id`, du plus récent au plus ancien."""
    pid = validate_program_id(program_id)
    runs_root = SETTINGS.artifacts_dir / pid / "runs"
    if not runs_root.is_dir():
        return []
    summaries: list[RunSummary] = []
    for p in sorted(runs_root.iterdir(), key=lambda p: p.name, reverse=True):
        if not p.is_dir():
            continue
        summaries.append(
            RunSummary(
                program_id=pid,
                timestamp=p.name,
                mode=_detect_mode(p),
                run_dir=str(p),
            )
        )
    return summaries


def load_run(program_id: str, timestamp: str) -> RunResult:
    """Recharge un run passé sans relancer le pipeline."""
    pid = validate_program_id(program_id)
    run_dir = _run_dir_for(pid, timestamp)
    if run_dir is None:
        raise RunnerError(f"Run introuvable: {program_id}/{timestamp}")

    mode = _detect_mode(run_dir)
    return collect_run_result(
        program_id=pid,
        run_dir=run_dir,
        mode=mode,
        duration_ms=0,
    )


def delete_run(program_id: str, timestamp: str) -> str:
    """Supprime le dossier d'un run passé.

    Opération purement locale à la webapp : on agit uniquement sur un
    sous-dossier de `artifacts/programs/<program_id>/runs/<timestamp>/`, jamais
    sur `programs/`, `scripts/`, ni sur d'autres `program_id`. Les garde-fous :

      - validation stricte du `program_id` et du format du `timestamp` ;
      - résolution du chemin et vérification qu'il reste bien sous
        `artifacts_dir` (pas de path traversal via lien symbolique) ;
      - suppression via `shutil.rmtree` sur ce chemin validé uniquement.
    """
    pid = validate_program_id(program_id)
    run_dir = _run_dir_for(pid, timestamp)
    if run_dir is None:
        raise RunnerError(f"Run introuvable: {program_id}/{timestamp}")

    resolved = run_dir.resolve()
    try:
        resolved.relative_to(SETTINGS.artifacts_dir.resolve())
    except ValueError as exc:
        raise RunnerError(
            f"Chemin invalide, refus de supprimer: {resolved}"
        ) from exc

    shutil.rmtree(resolved)
    return str(resolved)


def locate_classical_proof(program_id: str, timestamp: str) -> Path:
    """Retourne le chemin du fichier de preuve classique (`base_proof/*.json`).

    Utilisé par l'endpoint "voir tout" du frontend, qui a besoin de servir
    le contenu complet du fichier (trop gros pour l'aperçu de l'onglet Proof).
    Lève `RunnerError` si le run n'existe pas, ou s'il n'a pas de preuve
    classique (mode execute ou recursive sans base_proof).
    """
    pid = validate_program_id(program_id)
    run_dir = _run_dir_for(pid, timestamp)
    if run_dir is None:
        raise RunnerError(f"Run introuvable: {program_id}/{timestamp}")
    proof_path = _find_first_json(run_dir / "base_proof")
    if proof_path is None or not proof_path.is_file():
        raise RunnerError(
            f"Preuve classique introuvable pour le run {timestamp}."
        )
    return proof_path


def load_run_source(program_id: str, timestamp: str) -> str:
    """Retourne la source Cairo archivée par le bench pour ce run précis.

    Le script `run_workflow.sh` copie la source utilisée dans
    `<run_dir>/compiled/program.cairo`. C'est cette copie immuable qui est
    exposée ici, pas `programs/<program_id>.cairo` qui est volatile.
    """
    pid = validate_program_id(program_id)
    run_dir = _run_dir_for(pid, timestamp)
    if run_dir is None:
        raise RunnerError(f"Run introuvable: {program_id}/{timestamp}")

    source_path = run_dir / "compiled" / "program.cairo"
    if not source_path.is_file():
        raise RunnerError(
            f"Source archivée introuvable pour le run {timestamp} "
            "(compiled/program.cairo manquant)."
        )
    return source_path.read_text(encoding="utf-8")


def _extract_error_hint(logs: str) -> str:
    """Essaie d'extraire une ligne d'erreur lisible pour l'utilisateur.

    Les scripts shell préfixent les erreurs avec `ERROR:` ou `error:`.
    On remonte la dernière ligne pertinente ; sinon on retombe sur la queue
    du log brut.
    """
    candidates = [
        line.strip()
        for line in logs.splitlines()
        if line.strip()
        and ("error" in line.lower() or line.startswith("["))
    ]
    for line in reversed(candidates):
        low = line.lower()
        if "error" in low:
            return line
    if logs.strip():
        return logs.strip().splitlines()[-1]
    return "Échec sans message d'erreur explicite."
