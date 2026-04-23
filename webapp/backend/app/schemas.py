"""Contrat de données entre le frontend et le backend.

Le schéma est volontairement stable et extensible : les champs "phase 2"
(trace, commitments, fri, …) sont déjà prévus comme optionnels pour éviter
une rupture du frontend quand on les remplira.
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


ProvingMode = Literal["execute", "classical", "recursive"]
RunStatus = Literal["success", "error"]


class RunRequest(BaseModel):
    source_code: str = Field(..., description="Contenu du fichier .cairo")
    program_id: str = Field(
        "playground",
        description="Identifiant court du programme. Utilisé comme nom de fichier.",
    )
    args: str = Field(
        "",
        description="Arguments passés au programme Cairo (format `scarb execute --arguments`).",
    )
    mode: Optional[ProvingMode] = Field(
        None,
        description="Mode d'exécution. `None` utilise la valeur par défaut du backend.",
    )
    skip_env_check: bool = Field(
        True,
        description="Passer --skip-env-check au workflow pour éviter de payer la vérification à chaque run.",
    )


class ProofArtifact(BaseModel):
    """Représentation normalisée d'une preuve, quel que soit le mode."""

    kind: Literal["classical", "recursive", "none"] = "none"
    path: Optional[str] = None
    # Taille du fichier sérialisé sur disque (JSON). Utile pour comparer avec
    # la taille brute réelle de la preuve.
    size_bytes: Optional[int] = None
    preview: Optional[str] = Field(
        None,
        description="Aperçu texte (JSON tronqué) pour affichage dans le frontend.",
    )
    truncated: bool = False

    # Données brutes de la preuve, uniquement disponibles pour le mode récursif
    # où le binaire recursive_prover expose `proof_hex` + `proof_bytes`.
    raw_hex: Optional[str] = Field(
        None,
        description="Preuve récursive sérialisée en hex (contenu de proof_hex).",
    )
    raw_bytes: Optional[int] = Field(
        None,
        description="Taille de la preuve en octets bruts (len(proof_hex) / 2).",
    )


class RunResult(BaseModel):
    status: RunStatus
    mode: ProvingMode
    program_id: str
    run_dir: Optional[str] = None
    duration_ms: int

    # Output fonctionnel du programme Cairo (lignes extraites de scarb execute).
    program_output: Optional[str] = None

    # Preuve normalisée (classique ou récursive), volontairement simplifiée pour le MVP.
    proof: ProofArtifact = Field(default_factory=ProofArtifact)

    # Logs et metrics bruts, utiles pour le debug côté frontend.
    logs: Optional[str] = None
    metrics: Optional[dict] = None

    # Message d'erreur synthétique si status == "error".
    error: Optional[str] = None

    # Champs phase 2 — non remplis par le MVP, mais déclarés pour stabilité du contrat.
    trace_preview: Optional[dict] = None
    commitments: Optional[dict] = None
    fri: Optional[dict] = None


class HealthResponse(BaseModel):
    ok: bool
    bench_dir: str
    default_mode: ProvingMode
    run_workflow_exists: bool
    recursive_prover_built: bool


class RunSummary(BaseModel):
    """Entrée résumée pour la liste des runs passés (sélecteur frontend)."""

    program_id: str
    timestamp: str
    mode: ProvingMode
    run_dir: str
