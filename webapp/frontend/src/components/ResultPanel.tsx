"use client";

import { useState, type ReactNode } from "react";
import type { RunResult } from "@/lib/types";

type Tab = "output" | "proof" | "logs" | "metrics" | "phase2";

interface ResultPanelProps {
  result: RunResult | null;
  errorMessage: string | null;
  isRunning: boolean;
  // Slot optionnel injecté à droite des onglets (ex: sélecteur de run).
  headerRight?: ReactNode;
}

function formatBytes(n?: number | null) {
  if (!n && n !== 0) return "—";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

function EmptyState({ isRunning }: { isRunning: boolean }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center text-sm text-slate-500">
      {isRunning ? (
        <>
          <div className="h-5 w-5 animate-spin rounded-full border-2 border-accent border-t-transparent" />
          <div>Pipeline en cours…</div>
          <div className="text-xs text-slate-600">
            scarb execute → prove → verify
          </div>
        </>
      ) : (
        <>
          <div className="text-slate-400">
            Écris du code Cairo et lance{" "}
            <span className="text-accent-soft">Exécuter et prouver</span>.
          </div>
          <div className="text-xs text-slate-600">
            La sortie et la preuve s&apos;afficheront ici.
          </div>
        </>
      )}
    </div>
  );
}

function CodeBlock({ text }: { text: string }) {
  return (
    <pre className="h-full overflow-auto whitespace-pre-wrap break-words bg-surface p-4 font-mono text-xs leading-relaxed text-slate-200">
      {text}
    </pre>
  );
}

export function ResultPanel({
  result,
  errorMessage,
  isRunning,
  headerRight,
}: ResultPanelProps) {
  const [tab, setTab] = useState<Tab>("output");

  const tabs: { id: Tab; label: string; disabled?: boolean; hint?: string }[] = [
    { id: "output", label: "Output" },
    { id: "proof", label: "Proof" },
    { id: "logs", label: "Logs" },
    { id: "metrics", label: "Metrics" },
    { id: "phase2", label: "Phase 2", hint: "à venir" },
  ];

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center border-b border-surface-border bg-surface-raised">
        {tabs.map((t) => {
          const active = tab === t.id;
          return (
            <button
              key={t.id}
              type="button"
              onClick={() => setTab(t.id)}
              className={`relative px-4 py-2 text-xs font-medium transition ${
                active
                  ? "text-slate-100"
                  : "text-slate-400 hover:text-slate-200"
              }`}
            >
              {t.label}
              {t.hint && (
                <span className="ml-1 rounded bg-slate-700/50 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-slate-400">
                  {t.hint}
                </span>
              )}
              {active && (
                <span className="absolute inset-x-2 bottom-0 h-0.5 rounded bg-accent" />
              )}
            </button>
          );
        })}
        <div className="ml-auto flex items-center gap-3 pr-3 text-xs text-slate-500">
          {headerRight}
        </div>
      </div>

      <div className="min-h-0 flex-1">
        {errorMessage && (
          <div className="border-b border-err/30 bg-err/10 px-4 py-2 text-xs text-err">
            {errorMessage}
          </div>
        )}

        {!result && !errorMessage && <EmptyState isRunning={isRunning} />}

        {result && tab === "output" && (
          <CodeBlock
            text={result.program_output?.trim() || "(pas de sortie publique)"}
          />
        )}

        {result && tab === "proof" && (
          <div className="flex h-full flex-col">
            <div className="flex flex-wrap items-center gap-x-6 gap-y-1 border-b border-surface-border bg-surface-raised px-4 py-2 text-xs text-slate-400">
              <span>
                kind:{" "}
                <span className="font-mono text-slate-200">{result.proof.kind}</span>
              </span>
              {result.proof.kind === "recursive" ? (
                <span title="Taille réelle de la preuve (octets bruts).">
                  proof size:{" "}
                  <span className="font-mono text-slate-200">
                    {formatBytes(result.proof.raw_bytes ?? 0)}
                  </span>
                </span>
              ) : (
                <span>
                  size:{" "}
                  <span className="font-mono text-slate-200">
                    {formatBytes(result.proof.size_bytes ?? 0)}
                  </span>
                </span>
              )}
              {result.proof.kind === "recursive" && result.proof.size_bytes != null && (
                <span
                  className="text-slate-500"
                  title="Taille du fichier JSON sur disque (hex + métadonnées)."
                >
                  json file:{" "}
                  <span className="font-mono text-slate-400">
                    {formatBytes(result.proof.size_bytes)}
                  </span>
                </span>
              )}
              {result.proof.truncated && result.proof.kind !== "recursive" && (
                <span className="text-warn">preview tronqué</span>
              )}
              {result.proof.path && (
                <span className="truncate font-mono text-slate-500">
                  {proofLabel(result.proof.path)}
                </span>
              )}
              {result.proof.kind === "classical" &&
                result.run_dir &&
                (() => {
                  const ts = lastSegment(result.run_dir);
                  if (!ts) return null;
                  const url = `/api/runs/${encodeURIComponent(
                    ts,
                  )}/proof?program_id=${encodeURIComponent(result.program_id)}`;
                  return (
                    <a
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="ml-auto rounded border border-surface-border px-2 py-0.5 text-[10px] uppercase tracking-wide text-slate-300 transition hover:border-accent/60 hover:text-slate-100"
                      title="Ouvrir la preuve complète dans un nouvel onglet"
                    >
                      Voir tout
                    </a>
                  );
                })()}
            </div>
            <div className="min-h-0 flex-1">
              {result.proof.kind === "recursive" && result.proof.raw_hex ? (
                <CodeBlock text={formatHex(result.proof.raw_hex)} />
              ) : result.proof.preview ? (
                <CodeBlock text={result.proof.preview} />
              ) : (
                <div className="p-4 text-sm text-slate-500">
                  Aucune preuve pour ce mode.
                </div>
              )}
            </div>
          </div>
        )}

        {result && tab === "logs" && (
          <CodeBlock text={result.logs?.trim() || "(pas de logs)"} />
        )}

        {result && tab === "metrics" && (
          <CodeBlock
            text={
              result.metrics
                ? JSON.stringify(result.metrics, null, 2)
                : "(metrics non disponibles — le script n'en a pas écrit pour ce run)"
            }
          />
        )}

        {tab === "phase2" && (
          <div className="space-y-3 p-4 text-sm text-slate-400">
            <div>
              Cette zone accueillera les étapes internes du pipeline STARK :
            </div>
            <ul className="list-disc space-y-1 pl-6 text-xs text-slate-500">
              <li>portion de la trace exécutée</li>
              <li>commitments intermédiaires</li>
              <li>rounds de FRI</li>
              <li>vérification pas à pas</li>
              <li>benchmarks comparatifs</li>
            </ul>
            <div className="text-xs text-slate-600">
              Le contrat backend réserve déjà les champs {`{trace_preview, commitments, fri}`}
              pour éviter une rupture quand ces données seront exposées.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function formatHex(hex: string, groupSize = 2, groupsPerLine = 32): string {
  const clean = hex.trim().toLowerCase().replace(/[^0-9a-f]/g, "");
  if (!clean) return "";
  const groupRe = new RegExp(`.{1,${groupSize}}`, "g");
  const groups = clean.match(groupRe) ?? [];
  const lines: string[] = [];
  for (let i = 0; i < groups.length; i += groupsPerLine) {
    lines.push(groups.slice(i, i + groupsPerLine).join(" "));
  }
  return lines.join("\n");
}

function lastSegment(p: string): string | null {
  const parts = p.split("/").filter(Boolean);
  return parts.length ? parts[parts.length - 1] : null;
}

function proofLabel(proofPath: string): string {
  const parts = proofPath.split("/").filter(Boolean);
  const file = parts[parts.length - 1];
  const parent = parts[parts.length - 2];
  if (file && parent) return `${parent}/${file}`;
  return file ?? proofPath;
}
