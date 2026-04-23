"use client";

import type { ProvingMode } from "@/lib/types";

export type RunState = "idle" | "running" | "success" | "error";

interface TopBarProps {
  args: string;
  onArgsChange: (value: string) => void;
  mode: ProvingMode;
  onModeChange: (value: ProvingMode) => void;
  state: RunState;
  durationMs: number | null;
  backendOk: boolean | null;
  onRun: () => void;
}

const MODES: { value: ProvingMode; label: string; hint: string }[] = [
  { value: "execute", label: "Exécuter seul", hint: "scarb execute, pas de preuve" },
  { value: "classical", label: "Prouver (classique)", hint: "scarb prove + verify" },
  { value: "recursive", label: "Prouver (récursif)", hint: "stwo-circuits" },
];

function StatusBadge({ state }: { state: RunState }) {
  const map: Record<RunState, { label: string; classes: string }> = {
    idle: { label: "Prêt", classes: "bg-slate-700/40 text-slate-300" },
    running: { label: "Exécution…", classes: "bg-accent/20 text-accent-soft animate-pulse" },
    success: { label: "Succès", classes: "bg-ok/20 text-ok" },
    error: { label: "Erreur", classes: "bg-err/20 text-err" },
  };
  const s = map[state];
  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium ${s.classes}`}
    >
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {s.label}
    </span>
  );
}

export function TopBar(props: TopBarProps) {
  const {
    args,
    onArgsChange,
    mode,
    onModeChange,
    state,
    durationMs,
    backendOk,
    onRun,
  } = props;

  const disabled = state === "running" || backendOk === false;

  return (
    <header className="sticky top-0 z-20 flex flex-wrap items-center gap-3 border-b border-surface-border bg-surface-raised/90 px-5 py-3 backdrop-blur">
      <div className="flex items-center gap-2">
        <div className="flex h-8 w-8 items-center justify-center rounded-md bg-accent/20 text-accent-soft">
          <span className="font-mono text-sm">S</span>
        </div>
        <div className="leading-tight">
          <div className="text-sm font-semibold text-slate-100">STARK Playground</div>
          <div className="text-xs text-slate-400">
            Éditeur Cairo + prover
          </div>
        </div>
      </div>

      <div className="mx-2 hidden h-8 w-px bg-surface-border md:block" />

      <label className="flex items-center gap-2 text-xs text-slate-300">
        <span className="text-slate-400">arguments</span>
        <input
          className="w-48 rounded border border-surface-border bg-surface px-2 py-1 font-mono text-xs text-slate-100 focus:border-accent"
          value={args}
          onChange={(e) => onArgsChange(e.target.value)}
          placeholder="ex: 10"
          spellCheck={false}
        />
      </label>

      <label className="flex items-center gap-2 text-xs text-slate-300">
        <span className="text-slate-400">mode</span>
        <select
          className="rounded border border-surface-border bg-surface px-2 py-1 text-xs text-slate-100 focus:border-accent"
          value={mode}
          onChange={(e) => onModeChange(e.target.value as ProvingMode)}
        >
          {MODES.map((m) => (
            <option key={m.value} value={m.value}>
              {m.label}
            </option>
          ))}
        </select>
      </label>

      <div className="ml-auto flex items-center gap-3">
        <StatusBadge state={state} />
        {durationMs !== null && (
          <span className="text-xs text-slate-400 tabular-nums">
            {(durationMs / 1000).toFixed(1)}s
          </span>
        )}
        {backendOk === false && (
          <span className="text-xs text-err">
            Backend indisponible
          </span>
        )}
        <button
          type="button"
          onClick={onRun}
          disabled={disabled}
          className="rounded-md bg-accent px-4 py-1.5 text-sm font-semibold text-white shadow-md shadow-accent/30 transition hover:bg-accent-soft disabled:cursor-not-allowed disabled:bg-slate-600 disabled:shadow-none"
        >
          Exécuter et prouver
        </button>
      </div>
    </header>
  );
}
