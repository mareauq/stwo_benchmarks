import type {
  HealthResponse,
  RunRequest,
  RunResult,
  RunSummary,
} from "./types";

async function jsonFetch<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
  });
  if (!res.ok) {
    let detail = "";
    try {
      const body = (await res.json()) as { detail?: string };
      detail = body.detail ?? "";
    } catch {
      detail = await res.text();
    }
    throw new Error(detail || `${res.status} ${res.statusText}`);
  }
  return res.json() as Promise<T>;
}

export function getHealth(): Promise<HealthResponse> {
  return jsonFetch<HealthResponse>("/api/health");
}

export function runPipeline(req: RunRequest): Promise<RunResult> {
  return jsonFetch<RunResult>("/api/run", {
    method: "POST",
    body: JSON.stringify(req),
  });
}

export function listRuns(programId = "playground"): Promise<RunSummary[]> {
  const q = new URLSearchParams({ program_id: programId }).toString();
  return jsonFetch<RunSummary[]>(`/api/runs?${q}`);
}

export function loadRun(
  timestamp: string,
  programId = "playground",
): Promise<RunResult> {
  const q = new URLSearchParams({ program_id: programId }).toString();
  return jsonFetch<RunResult>(`/api/runs/${encodeURIComponent(timestamp)}?${q}`);
}

export interface RunSourceResponse {
  program_id: string;
  timestamp: string;
  source_code: string;
}

export function loadRunSource(
  timestamp: string,
  programId = "playground",
): Promise<RunSourceResponse> {
  const q = new URLSearchParams({ program_id: programId }).toString();
  return jsonFetch<RunSourceResponse>(
    `/api/runs/${encodeURIComponent(timestamp)}/source?${q}`,
  );
}

export interface RunDeleteResponse {
  program_id: string;
  timestamp: string;
  deleted_path: string;
}

export function deleteRun(
  timestamp: string,
  programId = "playground",
): Promise<RunDeleteResponse> {
  const q = new URLSearchParams({ program_id: programId }).toString();
  return jsonFetch<RunDeleteResponse>(
    `/api/runs/${encodeURIComponent(timestamp)}?${q}`,
    { method: "DELETE" },
  );
}
