import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "STARK Playground",
  description: "Illustration interactive du pipeline STARK via stwo_benchmarks.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr">
      <body className="min-h-screen bg-surface text-slate-200 antialiased">
        {children}
      </body>
    </html>
  );
}
