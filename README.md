# STWO Benchmarks — Cairo Proving Workbench

Repo de benchmarks pour programmes **Cairo 1** avec :
- exécution via `scarb execute`,
- preuve STARK de base via **`stwo-cairo`**,
- preuve récursive via **`stwo-circuits`**,
- archivage systématique des artefacts et métriques par run.

## Stack upstream

| Composant | Rôle dans ce repo |
|-----------|-------------------|
| `starkware-libs/cairo` + Scarb | Compilation et exécution des programmes Cairo 1 |
| `starkware-libs/stwo` | Moteur STARK générique |
| `starkware-libs/stwo-cairo` | Prover Cairo, adaptation VM, preuve de base |
| `starkware-libs/stwo-circuits` | Circuit de vérification récursive |

## Quick start

```bash
# 1. Préparer les dépendances vendoriées
bash scripts/setup_vendor.sh

# 2. Compiler le binaire de recursion
bash scripts/build_prover.sh

# 3. Vérifier l'environnement
bash scripts/check_env.sh
```

## Modes d'exécution

| Mode | Commande | Usage |
|------|----------|-------|
| Exécution seule | `bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --skip-prove` | Générer `prover_input.json`, les logs et l'output du programme |
| Preuve classique | `bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10" --classical` | `scarb prove` + `scarb verify`, sans recursion |
| Preuve récursive | `bash scripts/run_workflow.sh programs/fibonacci.cairo --args "10"` | Preuve de base + preuve récursive + vérification |

Le mode classique est le bon choix pour les gros programmes qui dépassent les
limites du circuit récursif.

## Vue d'ensemble du pipeline

```text
programs/foo.cairo
  -> prepare_program.sh
  -> .generated/programs/foo/app/
  -> scarb execute --target bootloader --output standard
  -> prover_input.json

Puis :
  - mode classique  : scarb prove -> scarb verify
  - mode récursif   : recursive_prover
        1. prove_cairo
        2. build_fixed_cairo_circuit -> prove_circuit_assignment
        3. verify_circuit
```

## Artefacts produits

Chaque run écrit un dossier sous `artifacts/programs/<program_id>/runs/<timestamp>/`.

| Chemin | Contenu |
|--------|---------|
| `compiled/` | source copiée, `Scarb.toml`, executable JSON |
| `inputs/arguments.txt` | arguments passés au programme |
| `outputs/program_output.txt` | sortie publique du programme |
| `cairo_vm/prover_input.json` | entrée du prover Cairo générée par `scarb execute` |
| `base_proof/proof.json` | preuve Cairo de base exportée par `recursive_prover` |
| `recursive_proof/proof.json` | preuve récursive sérialisée + métriques |
| `recursive_proof/vk.json` | clé de vérification du circuit récursif |
| `logs/` | stdout/stderr des différentes phases |
| `metrics/summary.json` | résumé des timings et tailles |

Notes sur les formats :
- `cairo_vm/prover_input.json` est l'artefact intermédiaire consommé par le
  prover Cairo.
- `base_proof/proof.json` n'est **pas** le même format que la preuve produite
  par `scarb prove` ; c'est l'export JSON de la structure Rust `CairoProof`
  utilisée par `recursive_prover`.
- `recursive_proof/proof.json` contient la preuve récursive sérialisée en hex et
  les métriques associées.

## Ajouter un benchmark

1. Créer un fichier dans `programs/` avec un unique `#[executable] fn main(...)`.
2. Éviter les syscalls.
3. Si l'objectif est de stresser le prover, préférer des sorties compactes ;
   les grosses sorties publiques stressent surtout l'I/O et la mémoire publique.
4. Lancer :

```bash
bash scripts/run_workflow.sh programs/my_program.cairo --args "42"
```

## Arborescence du repo

```text
programs/                Programmes Cairo benchmarkés
scripts/                 Scripts d'automatisation
templates/               Squelette Scarb injecté par programme
crates/recursive_prover/ Binaire Rust pour la recursion
vendor/                  Dépendances vendoriées
.generated/              Packages Scarb générés à la volée
.tools/                  Binaire installé de recursive_prover
artifacts/               Artefacts des runs
docs/                    Notes et documentation de référence
```

## Scripts principaux

| Script | Rôle |
|--------|------|
| `setup_vendor.sh` | Clone `stwo-circuits` au commit pin compatible |
| `build_prover.sh` | Compile et installe `recursive_prover` dans `.tools/bin/` |
| `prepare_program.sh` | Génère un package Scarb autour d'un fichier `.cairo` |
| `run_execute_pipeline.sh` | Lance `scarb execute` et archive les sorties |
| `run_classical_prove_pipeline.sh` | Lance `scarb prove` puis `scarb verify` |
| `run_prove_pipeline.sh` | Lance `recursive_prover` |
| `run_workflow.sh` | Point d'entrée principal |
| `check_env.sh` | Vérifie les versions attendues |
| `common.sh` | Helpers shell et versions pinées |

## Notes d'implémentation importantes

Ces points sont importants si `crates/recursive_prover/` doit être modifié :

1. **`ProofConfig::from_components` doit recevoir uniquement les composants activés.**
   Il faut filtrer via `enabled_components()` avant de construire la config de
   preuve pour la conversion de la preuve STARK vers le circuit.

2. **Le circuit récursif doit utiliser un seul contexte QM31 pour preprocess + prove.**
   Le même contexte est construit par `build_fixed_cairo_circuit`, finalisé par
   `PreprocessedCircuit::preprocess_circuit`, puis réutilisé par
   `prove_circuit_assignment`.

3. **`build_prover.sh` est la source de vérité pour le binaire utilisé.**
   Un `cargo build --release` manuel ne suffit pas ; il faut réinstaller le
   binaire dans `.tools/bin/`.

## Configuration du prover et limites

Le chemin récursif utilise actuellement `PreProcessedTraceVariant::CanonicalSmall`.
Cette variante est compatible avec l'intégration actuelle de `stwo-circuits`,
mais elle ne contient que les colonnes `seq_4`..`seq_20`.

Conséquence pratique :
- un programme peut être exécuté et prouvé classiquement bien au-delà de cette taille ;
- le mode récursif échoue dès qu'il a besoin d'une colonne `seq_21` ou plus ;
- le seuil exact dépend du programme, de ses builtins et de la forme de son
  trace, pas uniquement du nombre de steps affiché.

Variantes disponibles côté `stwo-cairo` :

| Variante | Colonnes `seq` | Pedersen | Nb colonnes | Cellules trace | Compatible recursion |
|----------|----------------|----------|-------------|----------------|---------------------|
| `CanonicalSmall` | `seq_4`..`seq_20` | oui (2^9) | 156 | 10M | **oui** |
| `CanonicalWithoutPedersen` | `seq_4`..`seq_25` | non | 105 | 73M | non |
| `Canonical` | `seq_4`..`seq_25` | oui (2^18) | 161 | 543M | non |

Pour un gros benchmark, utiliser le mode classique :

```bash
bash scripts/run_workflow.sh programs/fibonacci.cairo --args "2097152" --classical
```

Le paramètre `MAX_SEQUENCE_LOG_SIZE` dans `cairo_pcs_config()` contrôle la borne
supérieure du domaine PCS/FRI côté preuve de base. Il n'enlève pas la limite
structurelle imposée par `CanonicalSmall` pour la recursion.

La mémoire pic dépend fortement de la taille du trace et du parallélisme.
Limiter `RAYON_NUM_THREADS` peut aider sur les machines à mémoire contrainte.

## Versions pinées

Les versions critiques sont centralisées dans `scripts/common.sh` et
`crates/recursive_prover/Cargo.toml`.

| Composant | Version / révision |
|-----------|--------------------|
| `stwo` | 2.2.0 (crates.io) |
| `stwo-cairo` | git rev `0a5e70b7` |
| `stwo-circuits` | vendored, commit `b0ecaf8` |
| Rust nightly | `nightly-2025-06-23` |
| `scarb` | `nightly-2026-04-15` |
| `cairo_execute` | 2.17.0 |

Note sur `stwo-circuits` :
le projet évolue encore rapidement et son API Rust peut changer sur `main`
sans rester compatible avec `recursive_prover`. Ce repo se contraint donc à un
commit vendorié et fixé (`b0ecaf8`) pour garantir que `setup_vendor.sh`,
`build_prover.sh` et tout le pipeline restent reproductibles.

## Programmes de benchmark

### `fibonacci.cairo`

Benchmark minimal, utile comme référence simple.

- Entrée : `n`
- Sortie : `fibonacci(n)`

### `crypto.cairo`

Stress test crypto à sortie compacte combinant trois charges :

1. **Poseidon repeated permutations**
   `digest_{i+1} = Poseidon(digest_i, i)`.
2. **RSA-style modular exponentiation**
   carrés successifs en `u256` modulo l'ordre secp256k1.
3. **EC scalar multiplication**
   multiplication scalaire manuelle sur `y^2 = x^3 + x + 1`.

Paramètres :

| Paramètre | Effet |
|-----------|-------|
| `n_hash` | nombre de rounds Poseidon |
| `n_exp` | nombre de squarings RSA et d'additions EC |

Sortie :
`(poseidon_digest, rsa_result, ec_x, ec_y)`

### `identity_matrix.cairo`

Programme à sortie volumineuse :
- matrice identité `n x n`,
- chaîne de longueur `m`.

Utile pour observer le coût des gros outputs publics.

## Résultats de benchmark

### fibonacci

| n | Cairo steps | Base proof | Recursive proof | Verify | Base size | Recursive size |
|---|-------------|------------|-----------------|--------|-----------|----------------|
| 131 072 | 1 840 624 | ~38s | ~22s | 100ms | ~1.1 MB | ~61 KB |

### crypto

| (n_hash, n_exp) | Cairo steps | Builtins (range_check / poseidon) | Base proof | Recursive proof | Verify | Base size | Recursive size |
|-----------------|-------------|-----------------------------------|------------|-----------------|--------|-----------|----------------|
| (256, 256) | 118 911 | 27 151 / 512 | ~30s | ~31s | 87ms | ~1.4 MB | ~61 KB |
| (2048, 256) | 163 711 | 28 943 / 4 096 | ~42s | ~31s | 3ms | ~1.4 MB | ~61 KB |
| (16384, 256) | 522 111 | 43 279 / 32 768 | ~158s | ~32s | 88ms | ~1.4 MB | ~61 KB |
| (256, 2048) | 772 991 | 208 143 / 512 | ~32s | ~31s | 160ms | ~1.4 MB | ~61 KB |

Observations :

- **La preuve récursive reste ~constante pour une configuration récursive fixe.**
  Dans ces runs, son temps est ~31s et sa taille ~61 KB malgré des programmes
  et des entrées différentes.
- **Cette taille ne dépend pas directement du programme de base.**
  Elle dépend surtout de la configuration du circuit récursif et de ses
  paramètres de preuve (PCS/FRI, format de sérialisation, structure du circuit).
  Si ces paramètres changent, la taille de `recursive_proof` peut changer.
- **La preuve de base est le vrai goulot d'étranglement.**
  C'est elle qui croît avec les steps du programme Cairo.
- **Augmenter `n_hash` coûte surtout en builtin Poseidon.**
  Augmenter `n_exp` coûte surtout en range checks liés au `u256`.

## Références

- `docs/ecosystem.md` — vue d'ensemble des outils et composants STWO/Cairo utilisés ici.
