"use client";

import { useEffect, useRef, useState } from "react";

import type { RunSummary } from "@/lib/types";

interface RunSelectorProps {
  programId: string;
  // Timestamp du run actuellement affiché (ou null si pas encore de résultat).
  currentTimestamp: string | null;
  // Appelé quand l'utilisateur sélectionne un run passé dans la liste.
  onSelect: (summary: RunSummary) => void;
  // Appelé quand l'utilisateur veut charger dans l'éditeur la source archivée
  // d'un run (bouton "Code" à côté de l'entrée).
  onLoadSource: (summary: RunSummary) => void;
  // Appelé quand l'utilisateur supprime un run passé (bouton corbeille).
  onDelete: (summary: RunSummary) => void;
  // Liste des runs et fonction de rafraîchissement fournies par le parent.
  runs: RunSummary[];
  onRefresh: () => void;
  // Etat de chargement (ex: pendant le fetch /api/runs ou /api/runs/{ts}).
  isLoading: boolean;
}

export function RunSelector(props: RunSelectorProps) {
  const {
    programId,
    currentTimestamp,
    onSelect,
    onLoadSource,
    onDelete,
    runs,
    onRefresh,
    isLoading,
  } = props;

  const [open, setOpen] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onClickOutside(e: MouseEvent) {
      if (!wrapperRef.current) return;
      if (!wrapperRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    window.addEventListener("mousedown", onClickOutside);
    return () => window.removeEventListener("mousedown", onClickOutside);
  }, [open]);

  const label = currentTimestamp ?? "—";

  return (
    <div ref={wrapperRef} className="relative font-mono">
      <button
        type="button"
        onClick={() => {
          setOpen((v) => {
            const next = !v;
            if (next) onRefresh();
            return next;
          });
        }}
        className="inline-flex items-center gap-2 rounded border border-surface-border bg-surface px-2 py-1 text-xs text-slate-200 transition hover:border-accent/60"
        title={`Runs stockés pour ${programId}`}
      >
        <span className="text-slate-400">Run:</span>
        <span>{label}</span>
        <span className="text-slate-500">▾</span>
      </button>

      {open && (
        <div className="absolute right-0 z-30 mt-1 w-[28rem] max-w-[90vw] overflow-hidden rounded-md border border-surface-border bg-surface-raised shadow-lg">
          <div className="flex items-center justify-between border-b border-surface-border px-3 py-2 text-xs text-slate-400">
            <span>
              Runs — <span className="text-slate-300">{programId}</span>
              <span className="ml-2 text-slate-500">({runs.length})</span>
            </span>
            <button
              type="button"
              className="text-slate-500 transition hover:text-slate-200"
              onClick={onRefresh}
              title="Rafraîchir la liste"
            >
              ↻
            </button>
          </div>
          <div className="max-h-[28rem] overflow-auto">
            {isLoading && runs.length === 0 && (
              <div className="px-3 py-3 text-xs text-slate-500">Chargement…</div>
            )}
            {!isLoading && runs.length === 0 && (
              <div className="px-3 py-3 text-xs text-slate-500">
                Aucun run stocké pour ce programme.
              </div>
            )}
            {runs.map((r) => {
              const active = r.timestamp === currentTimestamp;
              return (
                <div
                  key={r.timestamp}
                  className={`flex w-full items-center gap-2 px-3 py-2 text-xs transition ${
                    active
                      ? "bg-accent/10 text-slate-100"
                      : "text-slate-300 hover:bg-surface"
                  }`}
                >
                  <button
                    type="button"
                    onClick={() => {
                      onSelect(r);
                      setOpen(false);
                    }}
                    className="flex flex-1 items-center justify-between gap-3 text-left"
                    title="Charger les résultats de ce run"
                  >
                    <span className="tabular-nums">{r.timestamp}</span>
                    <span className="rounded bg-slate-700/40 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-slate-400">
                      {r.mode}
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      onLoadSource(r);
                      setOpen(false);
                    }}
                    className="rounded border border-surface-border px-2 py-0.5 text-[10px] uppercase tracking-wide text-slate-400 transition hover:border-accent/60 hover:text-slate-100"
                    title="Charger dans l'éditeur la source Cairo archivée pour ce run"
                  >
                    Code
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      onDelete(r);
                    }}
                    className="rounded border border-transparent p-1 text-slate-500 transition hover:border-err/50 hover:text-err"
                    title="Supprimer ce run"
                    aria-label={`Supprimer le run ${r.timestamp}`}
                  >
                    <TrashIcon />
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function TrashIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-3.5 w-3.5"
      aria-hidden
    >
      <path d="M3 6h18" />
      <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
      <path d="M10 11v6" />
      <path d="M14 11v6" />
    </svg>
  );
}
