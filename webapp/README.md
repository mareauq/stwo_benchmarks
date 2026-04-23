# Webapp — STARK Playground

Couche de visualisation et d'exploration pédagogique construite par-dessus le
workbench `stwo_benchmarks`. Elle réutilise `scripts/run_workflow.sh` pour
exécuter et prouver du code Cairo écrit dans le navigateur, sans jamais se
substituer à la CLI.

> Ce dossier est **strictement optionnel**. Le workbench parent reste pleinement
> utilisable en ligne de commande sans installer Node ni Python web. Pour une
> description générale du bench, voir le [README principal](../README.md).

## Ce que fait la webapp

- éditeur Cairo (Monaco) avec mode `classical`, `recursive` ou `execute` ;
- exécution du pipeline via `run_workflow.sh`, sans modifier le moindre script
  existant ;
- panneaux `Output`, `Proof`, `Logs`, `Metrics` normalisés ;
- sélecteur des runs passés (`playground`) avec rechargement des résultats et
  du code source archivé, plus suppression d'un run ;
- vue dédiée "preuve brute en hex" pour le mode récursif, lien `Voir tout` vers
  le JSON complet pour le mode classique ;
- onglet `Phase 2` réservé pour la suite (trace, commitments, FRI,
  vérification pas à pas, benchmarks).

## Ce que la webapp ne fait pas

- Elle n'écrit **rien** sur disque tant que l'utilisateur ne clique pas sur
  `Exécuter et prouver`. L'éditeur est purement en mémoire tant qu'on n'a pas
  lancé un run.
- Elle ne modifie jamais les anciens runs : cliquer sur un run passé ou charger
  son code source archivé n'altère aucun artefact.
- Elle ne touche qu'à un unique fichier côté source : `programs/playground.cairo`
  (écrit uniquement au moment d'un run). Les autres programmes du bench
  (`fibonacci.cairo`, `crypto.cairo`, …) ne sont jamais écrits par la webapp.
- Elle ne supprime que des sous-dossiers de
  `artifacts/programs/playground/runs/<timestamp>/`, et uniquement sur action
  explicite de l'utilisateur.

## Contenu

- `backend/` — API FastAPI (Python) qui orchestre `run_workflow.sh` et retourne
  les artefacts (output, preuve, logs, metrics).
- `frontend/` — application Next.js (TypeScript, Tailwind, Monaco) : éditeur
  Cairo + panneaux `Output` / `Proof` / `Logs` / `Metrics` / `Phase 2` + sélecteur
  de runs passés.

## Architecture

```
Navigateur (Next.js)
   │  POST /api/run           { source_code, program_id, args, mode }
   │  GET  /api/runs          → liste des runs stockés (program_id = playground)
   │  GET  /api/runs/{ts}     → résultats d'un run passé
   │  GET  /api/runs/{ts}/source → source Cairo archivée du run
   │  GET  /api/runs/{ts}/proof  → preuve classique complète (JSON pretty)
   │  DELETE /api/runs/{ts}   → supprime un run stocké
   ▼
Backend FastAPI  (webapp/backend)
   │  écrit la source → ../programs/playground.cairo (uniquement à l'exécution)
   │  exécute bash ../scripts/run_workflow.sh ...
   │  lit  ../artifacts/programs/playground/runs/<timestamp>/*
   ▼
Réponse JSON  { status, output, proof, logs, metrics, run_dir, duration_ms, … }
```

Le format de réponse est extensible : la phase 2 (vue pas-à-pas) n'aura qu'à
remplir des champs optionnels déjà prévus dans le schéma Pydantic
(`trace_preview`, `commitments`, `fri`) sans casser le frontend.

### Invariants importants

- **`program_id` est figé à `playground`** côté UI : tous les runs webapp
  vivent sous `artifacts/programs/playground/runs/`. Le backend reste générique
  et accepte d'autres `program_id`, mais le frontend n'expose pas ce choix.
- **Le fichier `programs/playground.cairo` est volatile** : il est écrasé à
  chaque run. La référence historique d'un run, c'est la copie immuable
  archivée dans `artifacts/.../<timestamp>/compiled/program.cairo` par
  `run_workflow.sh`. C'est cette copie que la webapp relit quand on recharge
  un ancien run.

## Modes d'exécution

Alignés sur `run_workflow.sh` :

| Mode | Équivalent CLI | Usage |
|------|----------------|-------|
| `execute`  | `--skip-prove` | exécution Cairo seule, pas de preuve |
| `classical`| `--classical`  | `scarb prove` + `scarb verify` |
| `recursive`| (défaut workflow) | preuve de base + preuve récursive |

Le backend utilise `classical` par défaut : c'est le chemin le plus robuste
pour un programme écrit à la volée, indépendamment de la limite
`CanonicalSmall` documentée dans le [README du bench](../README.md).

### Affichage de la preuve

- **Mode récursif** : l'onglet `Proof` affiche la preuve brute (`proof_hex`)
  en hex groupé, avec la **taille réelle de la preuve** (`proof_bytes`) et, à
  titre indicatif, la taille du fichier JSON sur disque qui est plus grosse
  (encodage hex + métadonnées).
- **Mode classique** : aperçu tronqué du JSON produit par `scarb prove` + un
  bouton `Voir tout` qui ouvre le fichier complet pretty-printé dans un
  nouvel onglet.

## Prérequis

- Python 3.10+
- Node.js 18+
- Le bench parent doit être opérationnel :
  - `bash scripts/setup_vendor.sh`
  - `bash scripts/build_prover.sh` (nécessaire pour le mode récursif)
  - `bash scripts/check_env.sh` doit passer

## Démarrage

Depuis ce dossier (`webapp/`) :

```bash
# Backend
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000

# Frontend (autre terminal)
cd frontend
npm install
npm run dev
```

Puis ouvrir http://localhost:3000. Le frontend proxy `/api/*` vers le
backend en `127.0.0.1:8000` (voir `frontend/next.config.mjs`).

> Si le projet a été déplacé ou fusionné dans un autre repo, pense à
> **recréer le `.venv`** : les shebangs des scripts `pip` / `uvicorn` pointent
> vers l'ancien chemin absolu et cassent silencieusement. C'est une
> particularité des virtualenvs Python, pas un problème du backend.

## API côté backend

| Méthode | Route | Rôle |
|---------|-------|------|
| `GET`    | `/api/health`             | état du backend et du dépôt bench |
| `POST`   | `/api/run`                | lance `run_workflow.sh` et renvoie le résultat |
| `GET`    | `/api/runs`               | liste les runs stockés (avec mode détecté) |
| `GET`    | `/api/runs/{timestamp}`   | recharge un run passé (sans ré-exécution) |
| `GET`    | `/api/runs/{timestamp}/source` | renvoie la source Cairo archivée du run |
| `GET`    | `/api/runs/{timestamp}/proof`  | sert le JSON de preuve classique, pretty-printé |
| `DELETE` | `/api/runs/{timestamp}`   | supprime le dossier d'un run stocké |

Toutes les routes qui ciblent un run valident strictement `program_id` et
`timestamp`, puis résolvent le chemin et vérifient qu'il reste sous
`artifacts/programs/`. Pas de path traversal possible via lien symbolique
ou chemin crafted.

## Variables d'environnement (optionnelles)

Par défaut, le backend détecte seul la racine du bench à partir de son
propre chemin. Les variables suivantes restent honorées si tu veux surcharger
le comportement :

| Variable | Défaut | Rôle |
|----------|--------|------|
| `STWO_BENCHMARKS_DIR` | racine détectée automatiquement | racine du bench à piloter |
| `STARK_WEBAPP_DEFAULT_MODE` | `classical` | mode appliqué si non précisé |
| `STARK_WEBAPP_PROOF_PREVIEW_BYTES` | `65536` | taille max de l'aperçu de preuve classique |

## État

- [x] MVP : éditeur Cairo, `Exécuter et prouver`, panneaux Output / Proof /
      Logs / Metrics, sélecteur des runs passés (rechargement, chargement de la
      source archivée, suppression), preuve récursive brute en hex, `Voir tout`
      pour la preuve classique.
- [ ] Phase 2 : exposer la trace, les commitments, les étapes FRI, la
      vérification pas à pas et les benchmarks. Les champs correspondants
      (`trace_preview`, `commitments`, `fri`) sont déjà réservés dans le contrat
      backend/frontend pour éviter une rupture le jour où ils seront remplis.
