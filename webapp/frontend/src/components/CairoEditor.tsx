"use client";

import Editor from "@monaco-editor/react";

interface CairoEditorProps {
  value: string;
  onChange: (value: string) => void;
}

export function CairoEditor({ value, onChange }: CairoEditorProps) {
  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between border-b border-surface-border bg-surface-raised px-4 py-2">
        <div className="flex items-center gap-2 text-xs text-slate-300">
          <span className="h-2 w-2 rounded-full bg-accent" />
          <span className="font-mono">program.cairo</span>
        </div>
        <div className="text-xs text-slate-500">Cairo 1 · #[executable]</div>
      </div>
      <div className="min-h-0 flex-1">
        <Editor
          height="100%"
          defaultLanguage="rust"
          theme="vs-dark"
          value={value}
          onChange={(v) => onChange(v ?? "")}
          options={{
            fontSize: 13,
            minimap: { enabled: false },
            scrollBeyondLastLine: false,
            smoothScrolling: true,
            padding: { top: 12, bottom: 12 },
            fontFamily:
              "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
            tabSize: 4,
          }}
        />
      </div>
    </div>
  );
}
