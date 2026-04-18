# Context — Plateforme de benchmark pour le proving récursif STWO/Cairo

Ce document capture **tout ce qui a été appris** en tentant de construire une
plateforme modulaire de benchmark pour le proving récursif de programmes Cairo
avec la stack StarkWare (STWO + stwo-cairo + stwo_cairo_verifier).

Il est volontairement écrit pour être **consommé tel quel par un agent IA** qui
redémarrerait le projet `from scratch` : il y a des versions exactes, des
pointeurs précis vers les fichiers upstream problématiques, et un verdict clair
sur ce qui marche et ce qui ne marche pas.

---

## 1. Objectif du projet

Construire un banc d'essai reproductible pour **comparer les performances** de
plusieurs configurations de proving Cairo/STWO (pow_bits, log_blowup_factor,
n_queries, channel_hash, etc.), en exécutant sur des programmes Cairo triviaux
(fibonacci, hash, mul_mod…) les étapes suivantes :

1. Compilation du programme source `.cairo`.
2. Exécution en `proof_mode` via cairo-vm.
3. Génération de la preuve STWO de base.
4. Vérification de cette preuve.
5. **Exécution du `stwo_cairo_verifier` sur cette preuve** pour obtenir une
   trace « de vérification ».
6. **Preuve STWO de la vérification** (preuve récursive / rollup proof).
7. Vérification finale de la preuve récursive.

Le rapport de référence pour la compréhension globale de l'écosystème se trouve
dans `~/SNARKs/stwo.md` (copie locale recommandée dans le futur repo sous
`docs/ecosystem.md`).

---

## 2. Écosystème et terminologie

### 2.1 Projets upstream

| Projet                       | Rôle                                                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `starkware-libs/cairo`       | Compilateur Cairo **moderne** (Cairo 1). Sort Sierra/CASM/executables via Scarb.                                    |
| `starkware-libs/cairo-lang`  | Toolchain Python **legacy** (Cairo 0). Fournit `cairo-compile` pour produire du `compiled.json` Cairo 0.            |
| `starkware-libs/cairo-vm`    | VM Rust. `CairoRunner`, `all_cairo_stwo` layout, `proof_mode=true`.                                                 |
| `starkware-libs/stwo`        | Moteur STARK générique.                                                                                             |
| `starkware-libs/stwo-cairo`  | Spécialisation Cairo : adapter, prover, `cairo-air`, **`stwo_cairo_verifier` (programme Cairo)**.                   |
| `starkware-libs/stwo-circuits` | Circuits de vérification / recursion. Non utilisé ici.                                                            |
| `starkware-libs/proving-utils` | CLI `stwo-run-and-prove` (sur crates.io). **Cairo 0 uniquement** sur la version 1.2.2.                            |

### 2.2 Deux univers incompatibles

- **Cairo 0 (legacy)** : sources en syntaxe ancienne (`%builtins output …`,
  `func main()`), compilées par `cairo-compile` (Python) vers `compiled.json`.
  C'est le format attendu par les binaires et tests de stwo-cairo.
- **Cairo 1 (moderne)** : sources Cairo 1 avec `#[executable] fn main(...)`,
  compilées par Scarb vers `<prog>.executable.json`. C'est le workflow
  utilisateur principal, mais il est **mal pris en charge par stwo-cairo
  v1.2.2** (voir §6).

### 2.3 Formats de preuve

- `proof.json` : format « structuré » lisible par humain. Produit par
  `scarb prove` et par `run_and_prove --proof-format json`.
- `proof.cairo_serde.json` : **tableau plat de felts hex**. C'est le format
  consommé par le programme `stwo_cairo_verifier` via son argument
  `--arguments-file`. Produit par `run_and_prove --proof-format cairo-serde`.
- `prover_input.json` : sortie intermédiaire du `scarb prove` (ou de
  `stwo-vm-runner`). Contient l'état après adaptation. Pas nécessaire dans le
  workflow recommandé.

---

## 3. Version pinning — ce qui MARCHE ensemble

**Ces versions sont critiques.** Mélanger des versions proches casse la stack
de façons obscures (schémas JSON qui divergent, types qui renomment, etc.).

| Composant                | Version bloquante             | Justification                                                                      |
| ------------------------ | ----------------------------- | ---------------------------------------------------------------------------------- |
| `stwo-cairo`             | **tag `v1.2.2`**              | Dernière release testée. Les `main` post-1.2.2 changent le schéma de preuve.       |
| `scarb`                  | **`2.15.0`**                  | Doit matcher `cairo-lang-executable = "=2.15.0"` pinné par stwo-cairo 1.2.2. Si on utilise Scarb 2.17, l'`executable.json` a un champ `instruction_locations` que le prover rejette. |
| `cairo_execute` (Scarb dep) | **`2.15.0`**                | Idem — doit matcher la version de Scarb.                                           |
| Rust toolchain (prover)  | **`nightly-2025-06-23`**      | Pinné par `vendor/stwo-cairo/stwo_cairo_prover/rust-toolchain.toml`. Sans ce nightly, la build échoue avec des erreurs de borrow-checker / feature flags obscures. |
| Feature flag du verifier | **`qm31_opcode`** (ou `poseidon252_verifier`) | Le verifier requiert **exactement l'une** des deux. `qm31_opcode` est le choix par défaut pour l'instant. |

**Outillage système** : `asdf` pour scarb, `rustup` pour Rust nightly. Python 3
pour quelques scripts helpers. `git` (clone vendored). `jq` optionnel.

---

## 4. Pipeline qui FONCTIONNE (Cairo 0)

C'est le **chemin officiellement testé** par les fixtures de stwo-cairo
(`stwo_cairo_prover/test_data/test_prove_verify_*/`).

```text
programs/foo.cairo (Cairo 0, avec %builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod)
        │
        │ cairo-compile (Python, cairo-lang)
        ▼
foo_compiled.json  (Cairo 0 legacy JSON)
        │
        │ stwo-run-and-prove (crates.io proving-utils)  OR
        │ run_and_prove --program_type json (vendored stwo-cairo dev bin)
        ▼
proof.cairo_serde.json + auto-verify Rust
        │
        │ scarb execute sur vendor/stwo-cairo/stwo_cairo_verifier
        │ --features qm31_opcode --arguments-file proof.cairo_serde.json
        ▼
execution trace du verifier
        │
        │ scarb prove
        ▼
recursive_proof.json
        │
        │ scarb verify
        ▼
OK
```

**Exigence cruciale côté programme Cairo 0** : déclarer **les 11 builtins**
même si le programme n'en utilise que 2. Voir fixtures :

```cairo
%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod
```

C'est ce que font toutes les fixtures `test_prove_verify_*/compiled.json` de
stwo-cairo. C'est la seule configuration compatible avec le verifier Cairo.

---

## 5. Pipeline qui ne fonctionne QUE PARTIELLEMENT (Cairo 1)

Ce qu'on a tenté dans ce repo :

```text
programs/fibonacci.cairo (#[executable] fn main(n: u32) -> felt252)
        │
        │ scarb build (Scarb 2.15.0)
        ▼
fibonacci.executable.json  (entrypoint.builtins = [output, range_check])
        │
        │ run_and_prove --program_type executable --proof-format cairo-serde
        ▼
proof.cairo_serde.json                     ✅ GÉNÉRÉE
        │
        │ run_and_prove --verify (Rust verifier interne)
        ▼
OK                                         ✅ VÉRIFICATION RUST OK
        │
        │ scarb execute stwo_cairo_verifier --arguments-file <proof>
        ▼
❌ ASSERT_EQ échoue à pc=0:28329 : 0:18410 != 0:18411
```

La **preuve de base est valide** (le verifier Rust l'accepte). Elle est
**rejetée par le verifier Cairo** pour la raison structurelle décrite en §6.2.

---

## 6. Bugs et limitations fondamentales découverts dans stwo-cairo v1.2.2

### 6.1 Bug confirmé : `PublicSegmentContext::bootloader_context` hardcodé

**Fichier** : `stwo_cairo_prover/crates/adapter/src/adapter.rs`, ligne 44 (tag
v1.2.2).

```rust
// TODO(Ohad): take this from the input.
let public_segment_context = PublicSegmentContext::bootloader_context();
```

`bootloader_context()` marque les **11 builtins comme présents** systématique-
ment. Côté `extract_public_segments` (prover witness), la conséquence est que
le prover lit 11 paires de pointeurs en mémoire, même si le programme n'en a
écrit que 2. Les 9 paires restantes sont remplies avec des valeurs arbitraires
issues du hole-filling de cairo-vm. Résultat : `ecdsa.start=5, ecdsa.stop=10`
pour un fibonacci qui n'utilise pas ECDSA → le verifier Rust panique avec
`ECDSA segment is not empty`.

**Fix que j'ai appliqué** (non upstreamé) :

```rust
let public_segment_context = PublicSegmentContext::new(runner.get_program_builtins());
```

Plus un patch dans `crates/cairo-air/src/air.rs` (impl `CairoSerialize for
PublicSegmentRanges`) pour émettre des `SegmentRange { 0, 0 }` pour les
slots `None` au lieu de `.unwrap()` (évite la panique côté sérialisation
cairo-serde).

**Effet du fix** : la preuve de base est désormais générée et **auto-vérifiée**
par le verifier Rust interne. Mais le verifier Cairo reste incompatible
(§6.2).

### 6.2 Limitation architecturale : le verifier Cairo exige `n_builtins == 11`

**Fichier** : `stwo_cairo_verifier/crates/cairo_air/src/lib.cairo`.

- Le type `PublicSegmentRanges` Cairo a **11 champs `SegmentRange`** (pas
  `Option<SegmentRange>`) — ligne 599.
- La méthode `present_segments()` (ligne 621) append **tous** les segments,
  renvoyant toujours 11.
- `verify_program()` (ligne 535) fait :
  ```cairo
  let n_builtins = public_segments.present_segments().len();  // toujours 11
  assert!(program_value_1 == [n_builtins, 0, 0, 0, 0, 0, 0, 0]);
  ```
- Or, pour un programme Cairo 1 compilé par Scarb, le wrapper exécutable émet
  `ap += entrypoint.builtins.len()`, ce qui donne `[2, 0, ...]` pour fibonacci.
- **Assert échoue** → le verifier Cairo rejette la preuve.

**Conclusion** : `stwo_cairo_verifier` v1.2.2 ne peut vérifier que des preuves
de programmes qui déclarent **exactement 11 builtins**. Scarb n'offre aucun
moyen de forcer cette déclaration. D'où l'incompatibilité Cairo 1 ↔ recursion.

**Impact** : le pipeline récursif Cairo 1 est bloqué en amont tant que :
- stwo-cairo ne fixe pas `PublicSegmentRanges` côté verifier Cairo pour
  supporter un nombre variable de segments, **ou**
- Scarb permet de forcer la déclaration des 11 builtins dans l'entrypoint.

Suivre les TODOs upstream dans `adapter.rs` et probablement un issue tracker
stwo-cairo avant le prochain essai.

### 6.3 Autre piège : cairo-lang-executable pinné à une version EXACTE

`stwo-cairo v1.2.2/Cargo.toml` pin `cairo-lang-executable = "=2.15.0"`. Si on
construit l'`executable.json` avec un Scarb `>= 2.16`, le JSON contient un
champ `instruction_locations` introduit en 2.16, que le parser du prover
rejette avec `missing field 'instruction_locations'` (message trompeur — c'est
un champ nouveau qu'il ne sait pas ignorer, pas un champ manquant).

**Solution** : pinner `scarb 2.15.0` pour tout ce qui passe par stwo-cairo
v1.2.2. Changer le pin uniquement si on met à jour le tag stwo-cairo.

### 6.4 Dev binary `prove` vs `run_and_prove`

`vendor/stwo-cairo/stwo_cairo_prover/crates/dev_utils/src/bin/` contient deux
binaires :

- `prove` : prend un `prover_input.json` déjà adapté. Son flag `--verify`
  attend un format incompatible avec la sortie de Scarb → à éviter.
- `run_and_prove` : lit directement un `compiled.json` (Cairo 0) OU un
  `executable.json` (Cairo 1) via `--program_type json|executable`, exécute,
  adapte, prouve, optionnellement vérifie. **C'est le binaire à utiliser.**

### 6.5 Layout `all_cairo_stwo` et builtins absents

Le layout `all_cairo_stwo` de cairo-vm a `ecdsa: None` et `keccak: None`. Donc
cairo-vm ne crée PAS de runner pour ces deux builtins. Les 9 builtins « réels »
du layout sont : output, pedersen, range_check, bitwise, ec_op, poseidon,
range_check96, add_mod, mul_mod.

Les 11 slots des structures `PublicSegmentRanges` / `PublicSegmentContext`
gardent néanmoins ecdsa et keccak (pour compat avec des programmes Cairo 0 qui
déclarent `%builtins …ecdsa keccak…` de manière formelle sans réellement les
utiliser).

---

## 7. Recommandations pour un redémarrage `from scratch`

### 7.1 Décision principale : Cairo 0 ou Cairo 1 ?

**Aligné avec le rapport `stwo.md` et les fixtures upstream : Cairo 0.**

Justifications :

1. Les fixtures `test_prove_verify_*/` de stwo-cairo sont **toutes** en Cairo 0.
   Elles sont la seule configuration testée de bout en bout par stwo-cairo.
2. `proving-utils/stwo-run-and-prove` (recommandé par le rapport) n'accepte
   que Cairo 0.
3. Le verifier Cairo attend `n_builtins == 11`, ce que seul Cairo 0 permet de
   déclarer facilement (via `%builtins …`).
4. Pas besoin de vendorer/patcher stwo-cairo : les binaires crates.io
   suffisent.

**Contre-partie** : la syntaxe Cairo 0 est moins agréable, mais c'est un
détail pour un banc de benchmark.

### 7.2 Architecture recommandée

```
bench_stwo/
├── README.md
├── CONTEXT.md                      # ce document, à garder à jour
├── programs/
│   ├── fibonacci.cairo             # Cairo 0 avec %builtins ... (11 builtins)
│   ├── mul_mod.cairo
│   └── ...
├── scripts/
│   ├── common.sh                   # versions pinnées, helpers
│   ├── check_env.sh
│   ├── setup_toolchains.sh         # cairo-lang (python venv) + Rust nightly
│   ├── setup_stwo_cairo.sh         # clone + build binaries
│   ├── compile_program.sh          # cairo-compile
│   ├── run_base_pipeline.sh        # stwo-run-and-prove
│   ├── run_recursive_pipeline.sh   # scarb execute/prove/verify sur stwo_cairo_verifier
│   └── run_workflow.sh             # orchestrateur
├── .tools/                         # binaires compilés localement (stwo-run-and-prove)
├── vendor/                         # IMPORTANT: .gitignore; cloné par setup_stwo_cairo.sh
│   └── stwo-cairo/                 # tag v1.2.2
└── artifacts/                      # git-ignoré ; .runs/<timestamp>/{compiled,proofs,logs}
```

### 7.3 Pipeline idéal

1. `scripts/setup_toolchains.sh` : installe Python 3.11, un venv avec
   `cairo-lang==0.13.x` (fournit `cairo-compile`), et Rust nightly pinné.
2. `scripts/setup_stwo_cairo.sh` : clone `stwo-cairo@v1.2.2`, builde
   `run_and_prove` (ou installe `stwo-run-and-prove` depuis crates.io — les
   deux marchent pour Cairo 0), et installe le `stwo_cairo_verifier` Scarb
   workspace en préparant l'environnement Scarb 2.15.0.
3. Le pipeline de base : `cairo-compile foo.cairo --output foo.json
   --proof_mode`, puis `stwo-run-and-prove --program foo.json
   --proof-format cairo-serde --proof_path proof.serde.json --verify`.
4. Le pipeline récursif : `scarb --manifest-path vendor/stwo-cairo/
   stwo_cairo_verifier/Scarb.toml execute --features qm31_opcode
   --arguments-file proof.serde.json` → `scarb prove` → `scarb verify`.
5. Chaque run écrit un dossier timestampé sous `artifacts/`.

### 7.4 Paramètres de benchmark à exposer

Le binaire `run_and_prove` et `stwo-run-and-prove` acceptent (à vérifier selon
la version exacte) :

- `--proof-format {json,cairo-serde,binary}`
- `--pow_bits` (proof-of-work bits du channel)
- `--log_blowup_factor`
- `--n_queries`
- `--channel` (blake2s / poseidon252)
- `--preprocessed_trace` (Canonical / CanonicalWithoutPedersen)

Un runner de benchmark doit produire pour chaque combinaison :

- taille du proof
- temps proving
- temps verify (interne Rust)
- `execution_resources` de l'exec verifier Cairo
- taille du proof récursif
- temps proving récursif
- temps verify récursif

### 7.5 Anti-patterns à éviter

- ❌ **Ne pas utiliser Scarb pour compiler les programmes utilisateur** tant que
  le verifier Cairo exige `n_builtins == 11`. Cairo 1 est incompatible.
- ❌ **Ne pas appeler `scarb prove` pour le layer de base.** Le `prover_input.json`
  produit n'est pas consommé uniformément par toute la stack. Passer directement
  par `run_and_prove`.
- ❌ **Ne pas utiliser `prove --verify`** (l'autre dev binary, pas
  `run_and_prove`). Son `--verify` attend un format interne différent.
- ❌ **Ne pas supprimer `target/` du `stwo_cairo_verifier`** entre runs. Le
  verifier est un programme Cairo volumineux (~30s à compiler la première
  fois). Réutiliser la compilation.
- ❌ **Ne pas mixer plusieurs versions de Scarb** dans le même run. Utiliser
  `ASDF_SCARB_VERSION=2.15.0 scarb …` systématiquement.

---

## 8. Checklist minimale pour valider un nouveau setup

Un nouvel environnement est considéré fonctionnel si :

- [ ] `cairo-compile --version` renvoie `cairo-lang 0.13.x`.
- [ ] `scarb --version` renvoie `2.15.0` avec ASDF_SCARB_VERSION.
- [ ] `rustup toolchain list` inclut `nightly-2025-06-23`.
- [ ] `vendor/stwo-cairo` est au tag `v1.2.2` (`git describe --tags`).
- [ ] `stwo-run-and-prove` (ou `run_and_prove`) est compilé et exécutable.
- [ ] Le pipeline complet sur un programme Cairo 0 fibonacci avec 11 builtins
      passe : base proof générée + vérifiée, recursive proof générée + vérifiée.
- [ ] `scripts/check_env.sh` réussit sans ERROR.

---

## 9. Références internes

- Adapter bug (TODO non fixé) : `vendor/stwo-cairo/stwo_cairo_prover/crates/
  adapter/src/adapter.rs:44` (tag v1.2.2).
- Assertion rigide côté verifier Rust : `stwo_cairo_prover/crates/cairo-air/
  src/verifier.rs:154` (ECDSA) et `:160` (Keccak).
- Assertion rigide côté verifier Cairo : `stwo_cairo_verifier/crates/
  cairo_air/src/lib.cairo:550-553` (`n_builtins` via `present_segments().len()`).
- Fixtures Cairo 0 à imiter : `stwo_cairo_prover/test_data/test_prove_verify_*`.
- Source de vérité écosystème : `~/SNARKs/stwo.md` (copier dans le repo sous
  `docs/ecosystem.md`).

---

## 10. TL;DR pour l'agent qui reconstruit

1. Cloner stwo-cairo tag `v1.2.2` et pinner Scarb 2.15.0 + Rust
   nightly-2025-06-23.
2. Écrire les programmes de benchmark en **Cairo 0** avec déclaration
   explicite des 11 builtins.
3. Utiliser `stwo-run-and-prove` (crates.io) ou le dev binary `run_and_prove`
   (vendored) avec `--program_type json` (Cairo 0).
4. Pour la récursion, scarb execute + prove + verify sur
   `vendor/stwo-cairo/stwo_cairo_verifier` avec feature `qm31_opcode`.
5. Ne pas tenter Cairo 1 avec le verifier Cairo tant que §6.2 n'est pas
   résolu upstream.

---

## 11. Addendum — Architecture choisie pour `stwo_benchmarks`

### 11.1 Choix : hackx-zkcs style (Cairo 1 + stwo-circuits)

Le projet `stwo_benchmarks` a **délibérément divergé** de la recommandation
§7 (Cairo 0 + `stwo_cairo_verifier`) en adoptant l'approche « hackx-zkcs » :

- **Cairo 1** avec `#[executable] fn main(...)`, compilé par Scarb.
- **`scarb execute --target bootloader --output standard`** pour produire un
  `prover_input.json`.
- **`stwo-circuits`** (vendored, branche `main`) pour la recursion au lieu
  du `stwo_cairo_verifier` Cairo. Cela contourne la limitation §6.2
  (`n_builtins == 11`) car la vérification se fait entièrement en Rust via
  un circuit arithmétique, sans passer par le programme Cairo.
- **Driver Rust `recursive_prover`** (`crates/recursive_prover/`) qui
  enchaîne les 3 phases : `prove_cairo` → circuit proving → `verify_circuit`.

### 11.2 Versions pinnées (stwo_benchmarks)

| Composant             | Version                                     |
| --------------------- | ------------------------------------------- |
| `stwo`                | 2.2.0 (crates.io)                           |
| `stwo-cairo`          | git rev `0a5e70b7` (post-v1.2.2)            |
| `stwo-circuits`       | vendored, branche `main`                    |
| `scarb`               | `nightly-2026-04-15` (via asdf)             |
| `cairo_execute`       | 2.17.0                                      |
| Rust toolchain        | `nightly-2025-06-23`                        |

### 11.3 Pièges rencontrés et résolus lors de l'implémentation

1. **`ProofConfig::from_components` — composants activés uniquement.**
   Il faut filtrer les composants via `enabled_components()` avant de
   construire le `ProofConfig`. Passer la liste complète (`all_components`)
   cause un mismatch dans le nombre de queried values lors de la conversion
   de la preuve STARK en format circuit (`proof_from_stark_proof`).

2. **Contexte unique pour preprocess + prove.**
   Le `PreprocessedCircuit::preprocess_circuit` appelle `finalize_context`
   en interne (padding des composants, hashing des constantes). Les `values()`
   du contexte ne sont valides qu'après cette finalisation. Il est donc
   **impératif** d'utiliser un seul contexte QM31 : construire le circuit
   (`build_fixed_cairo_circuit`), vérifier sa validité, puis appeler
   `preprocess_circuit` sur ce même contexte, et enfin passer ses `values()`
   à `prove_circuit_assignment`. Utiliser deux contextes séparés (un NoValue
   pour le preprocessing, un QM31 pour les valeurs) provoque un dépassement
   d'index dans le witness generator (`qm31_ops.rs`).

3. **Binaire installé vs compilé.**
   `build_prover.sh` copie le binaire de `target/release/` vers
   `.tools/bin/`. Un `cargo build --release` manuel ne met pas à jour
   `.tools/bin/` — penser à relancer `build_prover.sh` ou copier
   manuellement.

### 11.4 Résultats de validation (fibonacci, n=10)

```
Cairo steps:             5 756
Base proof (stwo-cairo): ~7s, ~1 MB
Recursive proof:         ~19s, ~61 KB
Verification:            ~180ms
```

### 11.5 Recommandations §7 encore valides

Les anti-patterns §7.5 restent pertinents sauf ceux spécifiques à Cairo 0 :

- ✅ **Ne pas mixer les versions de Scarb** entre runs.
- ✅ **Ne pas supprimer `target/`** inutilement (cache de compilation).
- ⚠️ §7.5 ❌ « Ne pas utiliser Scarb pour compiler les programmes utilisateur »
  — **ne s'applique plus** : Cairo 1 + stwo-circuits fonctionne.
- ⚠️ §7.1 « Cairo 0 » — **ne s'applique plus** : Cairo 1 est le choix retenu.
