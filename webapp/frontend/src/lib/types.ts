// Miroir TypeScript du contrat Pydantic backend/app/schemas.py.
// On garde les champs "phase 2" optionnels pour pouvoir les afficher plus tard
// sans changer le frontend.

export type ProvingMode = "execute" | "classical" | "recursive";

export type RunStatus = "success" | "error";

export interface RunRequest {
  source_code: string;
  program_id?: string;
  args?: string;
  mode?: ProvingMode;
  skip_env_check?: boolean;
}

export interface ProofArtifact {
  kind: "classical" | "recursive" | "none";
  path?: string | null;
  // Taille du fichier sérialisé sur disque (JSON, hex + métadonnées).
  size_bytes?: number | null;
  preview?: string | null;
  truncated?: boolean;
  // Seulement rempli pour le mode récursif.
  raw_hex?: string | null;
  raw_bytes?: number | null;
}

export interface RunResult {
  status: RunStatus;
  mode: ProvingMode;
  program_id: string;
  run_dir?: string | null;
  duration_ms: number;
  program_output?: string | null;
  proof: ProofArtifact;
  logs?: string | null;
  metrics?: Record<string, unknown> | null;
  error?: string | null;

  // Phase 2 — réservés mais non remplis par le MVP.
  trace_preview?: Record<string, unknown> | null;
  commitments?: Record<string, unknown> | null;
  fri?: Record<string, unknown> | null;
}

export interface HealthResponse {
  ok: boolean;
  bench_dir: string;
  default_mode: ProvingMode;
  run_workflow_exists: boolean;
  recursive_prover_built: boolean;
}

export interface RunSummary {
  program_id: string;
  timestamp: string;
  mode: ProvingMode;
  run_dir: string;
}

export const DEFAULT_CAIRO_SOURCE = `/// Calcule le n-ieme nombre de Fibonacci de maniere iterative.
#[executable]
fn main(n: u32) -> felt252 {
    let mut a: felt252 = 0;
    let mut b: felt252 = 1;
    let mut i: u32 = 0;
    while i < n {
        let c = a + b;
        a = b;
        b = c;
        i += 1;
    };
    a
}
`;
