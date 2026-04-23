"""Point d'entrée FastAPI.

API volontairement minimaliste pour le MVP :
  GET  /api/health  -> état du backend et du dépôt bench
  POST /api/run     -> exécution + preuve en synchrone, réponse JSON unique
"""

from __future__ import annotations

import json

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response

from pydantic import BaseModel

from .config import SETTINGS
from .runner import (
    RunnerError,
    delete_run,
    list_runs,
    load_run,
    load_run_source,
    locate_classical_proof,
    run_pipeline,
)
from .schemas import HealthResponse, RunRequest, RunResult, RunSummary


class RunSourceResponse(BaseModel):
    program_id: str
    timestamp: str
    source_code: str


class RunDeleteResponse(BaseModel):
    program_id: str
    timestamp: str
    deleted_path: str


app = FastAPI(
    title="STARK Webapp Backend",
    version="0.1.0",
    description="Orchestrateur léger autour de stwo_benchmarks/run_workflow.sh.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        ok=SETTINGS.run_workflow_script.is_file(),
        bench_dir=str(SETTINGS.bench_dir),
        default_mode=SETTINGS.default_mode,  # type: ignore[arg-type]
        run_workflow_exists=SETTINGS.run_workflow_script.is_file(),
        recursive_prover_built=(SETTINGS.bench_dir / ".tools" / "bin" / "recursive_prover").is_file(),
    )


@app.post("/api/run", response_model=RunResult)
def run(req: RunRequest) -> RunResult:
    try:
        return run_pipeline(req)
    except RunnerError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err
    except Exception as err:  # noqa: BLE001 — on remonte une 500 propre
        raise HTTPException(status_code=500, detail=f"Erreur interne: {err}") from err


@app.get("/api/runs", response_model=list[RunSummary])
def list_past_runs(program_id: str = "playground") -> list[RunSummary]:
    """Liste les runs stockés pour un programme donné.

    Lecture seule : aucun run n'est relancé, aucun artefact n'est créé. Utilisé
    par le s\u00e9lecteur "Run" du frontend pour recharger un run pass\u00e9.
    """
    try:
        return list_runs(program_id)
    except RunnerError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err


@app.get("/api/runs/{timestamp}", response_model=RunResult)
def get_past_run(timestamp: str, program_id: str = "playground") -> RunResult:
    """Recharge le résultat d'un run déjà existant (pas de ré-exécution)."""
    try:
        return load_run(program_id, timestamp)
    except RunnerError as err:
        raise HTTPException(status_code=404, detail=str(err)) from err


@app.get("/api/runs/{timestamp}/source", response_model=RunSourceResponse)
def get_past_run_source(
    timestamp: str,
    program_id: str = "playground",
) -> RunSourceResponse:
    """Retourne la source Cairo archivée par le bench pour ce run précis.

    Permet au frontend de recharger le code exact qui a produit ce run, sans
    toucher à `programs/<program_id>.cairo` ni à aucun artefact.
    """
    try:
        source = load_run_source(program_id, timestamp)
    except RunnerError as err:
        raise HTTPException(status_code=404, detail=str(err)) from err
    return RunSourceResponse(
        program_id=program_id,
        timestamp=timestamp,
        source_code=source,
    )


@app.get("/api/runs/{timestamp}/proof")
def get_past_run_proof(
    timestamp: str,
    program_id: str = "playground",
) -> Response:
    """Sert la preuve classique complète d'un run, au format JSON indenté.

    Utilisé par le bouton "Voir tout" du frontend : la route est conçue pour
    être ouverte directement dans un nouvel onglet du navigateur (Content-Type
    `application/json`, réponse non mise en cache).
    """
    try:
        proof_path = locate_classical_proof(program_id, timestamp)
    except RunnerError as err:
        raise HTTPException(status_code=404, detail=str(err)) from err

    try:
        parsed = json.loads(proof_path.read_text(encoding="utf-8"))
        body = json.dumps(parsed, indent=2, ensure_ascii=False)
    except (OSError, json.JSONDecodeError):
        # Si le JSON est invalide ou illisible, on renvoie le contenu brut.
        body = proof_path.read_text(encoding="utf-8", errors="replace")

    return Response(
        content=body,
        media_type="application/json",
        headers={"Cache-Control": "no-store"},
    )


@app.delete("/api/runs/{timestamp}", response_model=RunDeleteResponse)
def delete_past_run(
    timestamp: str,
    program_id: str = "playground",
) -> RunDeleteResponse:
    """Supprime un run archivé.

    Action destructive volontairement limitée : seul le dossier
    `artifacts/programs/<program_id>/runs/<timestamp>/` est effacé, après
    validation stricte et résolution confinée à `artifacts_dir`.
    """
    try:
        deleted = delete_run(program_id, timestamp)
    except RunnerError as err:
        raise HTTPException(status_code=404, detail=str(err)) from err
    except OSError as err:
        raise HTTPException(
            status_code=500,
            detail=f"Suppression impossible: {err}",
        ) from err
    return RunDeleteResponse(
        program_id=program_id,
        timestamp=timestamp,
        deleted_path=deleted,
    )
