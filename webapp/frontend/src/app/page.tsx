"use client";

import { useEffect, useState } from "react";

import { CairoEditor } from "@/components/CairoEditor";
import { ResultPanel } from "@/components/ResultPanel";
import { RunSelector } from "@/components/RunSelector";
import { TopBar, type RunState } from "@/components/TopBar";
import {
  deleteRun,
  getHealth,
  listRuns,
  loadRun,
  loadRunSource,
  runPipeline,
} from "@/lib/api";
import {
  DEFAULT_CAIRO_SOURCE,
  type ProvingMode,
  type RunResult,
  type RunSummary,
} from "@/lib/types";

const PLAYGROUND_PROGRAM_ID = "playground";

function currentTimestamp(result: RunResult | null): string | null {
  if (!result?.run_dir) return null;
  const parts = result.run_dir.split("/").filter(Boolean);
  return parts[parts.length - 1] ?? null;
}

export default function HomePage() {
  const [source, setSource] = useState<string>(DEFAULT_CAIRO_SOURCE);
  // Source de référence : code dont on sait qu'il correspond au résultat
  // affiché à droite (soit le dernier run lancé, soit un run passé rechargé).
  // Sert à détecter "l'éditeur a été modifié depuis" sans écrire sur disque.
  const [displayedSource, setDisplayedSource] = useState<string>(
    DEFAULT_CAIRO_SOURCE,
  );
  const [args, setArgs] = useState<string>("10");
  const [mode, setMode] = useState<ProvingMode>("classical");

  const [state, setState] = useState<RunState>("idle");
  const [durationMs, setDurationMs] = useState<number | null>(null);
  const [result, setResult] = useState<RunResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [backendOk, setBackendOk] = useState<boolean | null>(null);

  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [runsLoading, setRunsLoading] = useState<boolean>(false);

  useEffect(() => {
    getHealth()
      .then((h) => {
        setBackendOk(h.ok);
        if (!h.ok) {
          setErrorMessage(
            `Le script run_workflow.sh est introuvable dans ${h.bench_dir}. ` +
              "Vérifie STWO_BENCHMARKS_DIR côté backend.",
          );
        } else {
          void refreshRuns();
        }
      })
      .catch(() => {
        setBackendOk(false);
        setErrorMessage(
          "Impossible de joindre le backend. Lance `uvicorn app.main:app --port 8000` dans backend/.",
        );
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleRun() {
    setState("running");
    setErrorMessage(null);
    setResult(null);
    setDurationMs(null);
    const executedSource = source;
    try {
      const res = await runPipeline({
        source_code: executedSource,
        program_id: PLAYGROUND_PROGRAM_ID,
        args,
        mode,
      });
      setResult(res);
      setDurationMs(res.duration_ms);
      if (res.status === "success") {
        setState("success");
      } else {
        setState("error");
        setErrorMessage(res.error ?? "Échec du pipeline.");
      }
      setDisplayedSource(executedSource);
      void refreshRuns();
    } catch (err) {
      setState("error");
      const msg = err instanceof Error ? err.message : String(err);
      setErrorMessage(msg);
    }
  }

  async function refreshRuns() {
    setRunsLoading(true);
    try {
      const list = await listRuns(PLAYGROUND_PROGRAM_ID);
      setRuns(list);
    } catch {
      // On reste silencieux : la liste est une aide, pas un blocage.
    } finally {
      setRunsLoading(false);
    }
  }

  async function handleSelectRun(summary: RunSummary) {
    // Le clic sur la ligne d'un run charge TOUT le run : résultats + source
    // archivée. On ne persiste rien sur disque (cf. backend).
    const dirty = source !== displayedSource;
    if (dirty) {
      const ok = window.confirm(
        "L'éditeur contient des modifications non exécutées. " +
          "Charger ce run va remplacer le code actuel par la source archivée. " +
          "Continuer ?",
      );
      if (!ok) return;
    }

    setState("running");
    setErrorMessage(null);
    try {
      const [res, src] = await Promise.all([
        loadRun(summary.timestamp, summary.program_id),
        loadRunSource(summary.timestamp, summary.program_id).catch(() => null),
      ]);
      setResult(res);
      setDurationMs(null);
      setMode(res.mode);
      setState(res.status === "success" ? "success" : "error");
      if (res.status === "error") {
        setErrorMessage(res.error ?? "Run en erreur.");
      }
      if (src) {
        setSource(src.source_code);
        setDisplayedSource(src.source_code);
      } else {
        setErrorMessage(
          `Résultats chargés, mais la source archivée est introuvable pour ${summary.timestamp}.`,
        );
      }
    } catch (err) {
      setState("error");
      const msg = err instanceof Error ? err.message : String(err);
      setErrorMessage(msg);
    }
  }

  async function handleDeleteRun(summary: RunSummary) {
    const ok = window.confirm(
      `Supprimer définitivement le run ${summary.timestamp} ?\n` +
        "Les artefacts de ce run seront effacés du disque.",
    );
    if (!ok) return;
    try {
      await deleteRun(summary.timestamp, summary.program_id);
      setRuns((prev) => prev.filter((r) => r.timestamp !== summary.timestamp));
      if (currentTimestamp(result) === summary.timestamp) {
        setResult(null);
        setDurationMs(null);
        setState("idle");
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setErrorMessage(`Suppression impossible pour ${summary.timestamp}: ${msg}`);
    }
  }

  async function handleLoadSource(summary: RunSummary) {
    // Action secondaire : on récupère seulement la source dans l'éditeur,
    // sans toucher aux panneaux de résultats. Pas de dirty check : l'utilisateur
    // demande explicitement à remplacer son code par celui d'un ancien run.
    setErrorMessage(null);
    try {
      const res = await loadRunSource(summary.timestamp, summary.program_id);
      setSource(res.source_code);
      // Si l'utilisateur importe la source du run actuellement affiché à droite,
      // il repasse en état "propre". Sinon l'éditeur sera marqué dirty par
      // rapport au résultat actuel (ce qui est correct).
      if (summary.timestamp === currentTimestamp(result)) {
        setDisplayedSource(res.source_code);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setErrorMessage(
        `Impossible de charger le code archivé pour ${summary.timestamp}: ${msg}`,
      );
    }
  }

  return (
    <div className="flex h-screen flex-col">
      <TopBar
        args={args}
        onArgsChange={setArgs}
        mode={mode}
        onModeChange={setMode}
        state={state}
        durationMs={durationMs}
        backendOk={backendOk}
        onRun={handleRun}
      />
      <main className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-2">
        <section className="min-h-0 border-surface-border lg:border-r">
          <CairoEditor value={source} onChange={setSource} />
        </section>
        <section className="min-h-0">
          <ResultPanel
            result={result}
            errorMessage={errorMessage}
            isRunning={state === "running"}
            headerRight={
              <RunSelector
                programId={PLAYGROUND_PROGRAM_ID}
                currentTimestamp={currentTimestamp(result)}
                runs={runs}
                isLoading={runsLoading}
                onRefresh={refreshRuns}
                onSelect={handleSelectRun}
                onLoadSource={handleLoadSource}
                onDelete={handleDeleteRun}
              />
            }
          />
        </section>
      </main>
    </div>
  );
}
