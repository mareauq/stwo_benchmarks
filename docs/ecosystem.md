# Ecosysteme Cairo / Stwo / proving-utils

Ce document decrit le role des principaux outils de l'ecosysteme `starkware-libs` autour de Cairo et Stwo, leurs dependances mutuelles, ainsi que le pipeline complet pour :

1. ecrire un programme Cairo,
2. le compiler,
3. l'executer de facon prouvable,
4. generer une preuve,
5. verifier cette preuve,
6. construire une verification recursive.

L'objectif est de clarifier ce que fait chaque projet, ce qu'il ne fait pas, et a quel moment il intervient.

---

## 1. Vue d'ensemble

Il faut distinguer plusieurs couches :

- couche langage / compilation
- couche execution
- couche adaptation au proving
- couche proving
- couche verification
- couche recursion / circuits
- couche outillage / orchestration

Les projets principaux sont :

- `cairo`
- `cairo-lang`
- `cairo-vm`
- `stwo`
- `stwo-cairo`
- `stwo-circuits`
- `proving-utils`
- `cairo_native`

Le point essentiel est le suivant :

- `cairo` sert a ecrire et compiler du Cairo moderne
- `cairo-vm` sert a executer des programmes Cairo compiles
- `stwo` est le moteur STARK generique
- `stwo-cairo` specialise Stwo pour les programmes Cairo
- `stwo-circuits` sert surtout aux circuits de verification et a la recursion
- `proving-utils` orchestre un pipeline utilisable directement en CLI

---

## 2. Description detaillee de chaque outil

### 2.1 `cairo`

Repo : `starkware-libs/cairo`

Role principal :

- compilateur et toolchain du langage Cairo moderne
- compilation source Cairo -> Sierra / CASM / executables / artefacts divers
- outils de test et d'execution associes a la toolchain

Ce que fait `cairo` :

- compile du code source `.cairo`
- peut produire du Sierra
- peut produire du CASM
- fournit des outils comme `cairo-run`, `cairo-test`, `starknet-compile`

Ce que `cairo` ne fait pas directement :

- il n'est pas le moteur principal du proving Stwo
- il n'est pas l'orchestrateur de bout en bout de la preuve recursive

Quand l'utiliser :

- quand ton point de depart est un programme source Cairo
- quand tu veux compiler, tester, preparer les artefacts entres dans le pipeline

Mise en fonctionnement typique :

1. ecriture du programme avec Scarb ou directement avec la toolchain Cairo
2. compilation du programme
3. production d'un artefact compatible avec l'execution ulterieure

Sorties typiques :

- source `.cairo`
- `Sierra`
- `CASM`
- executable/artefact compile selon le mode choisi

---

### 2.2 `cairo-lang`

Repo : `starkware-libs/cairo-lang`

Role principal :

- ancien stack Cairo historique en Python
- reference legacy, surtout importante pour Cairo 0 et certains workflows historiques

Ce que fait `cairo-lang` :

- ancien compilateur / ancien runtime Python
- base historique de nombreux anciens workflows

Ce que `cairo-lang` ne represente plus :

- ce n'est plus la toolchain moderne principale pour l'ecosysteme Rust courant

Quand l'utiliser :

- surtout dans un contexte legacy
- pour comprendre d'anciens pipelines Cairo 0

Remarque importante :

Le nom `cairo-lang-*` apparait encore dans des crates Rust modernes, mais cela ne signifie pas qu'on repasse par le vieux repo Python comme brique principale d'orchestration.

---

### 2.3 `cairo-vm`

Repo : `starkware-libs/cairo-vm`

Role principal :

- machine virtuelle Rust pour executer des programmes Cairo compiles

Ce que fait `cairo-vm` :

- charge un programme compile
- l'execute avec un layout donne
- gere le `proof_mode`
- peut produire :
  - output du programme
  - trace
  - memory
  - AIR public input
  - AIR private input
  - Cairo PIE

Ce que `cairo-vm` ne fait pas seul :

- il ne produit pas a lui seul la preuve Stwo finale
- il ne fait pas seul la recursion

Quand l'utiliser :

- quand tu veux executer le programme compile
- quand tu veux obtenir des artefacts d'execution exploitables pour le proving

Mise en fonctionnement typique :

1. charger un artefact compile
2. fournir les inputs
3. choisir un layout
4. executer le programme
5. recuperer output, trace, memory, ou AIR inputs

Sorties typiques :

- output JSON
- execution resources
- trace binaire
- memory binaire
- AIR public input JSON
- AIR private input JSON
- Cairo PIE

---

### 2.4 `stwo`

Repo : `starkware-libs/stwo`

Role principal :

- moteur STARK generique
- implementation du prover/verifier de bas niveau

Ce que fait `stwo` :

- fournit des primitives cryptographiques et de proving generiques
- sert de base commune aux preuves construites par les couches superieures

Ce que `stwo` ne fait pas directement :

- il ne comprend pas "nativement" un programme Cairo compile
- il n'orchestre pas le pipeline applicatif Cairo

Quand l'utiliser :

- quand on developpe le moteur de preuve lui-meme
- quand on travaille sur les briques bas niveau du prover / verifier

Sorties conceptuelles :

- structures de preuve STARK
- engagements / PCS / FRI / objets lies au prover

---

### 2.5 `stwo-cairo`

Repo : `starkware-libs/stwo-cairo`

Role principal :

- adaptation de Stwo au cas particulier de Cairo

Ce que fait `stwo-cairo` :

- transforme les donnees d'execution Cairo en donnees consommables par le prover
- fournit les crates d'adaptation, de proving, de serialisation et de verification

Sous-composants importants :

- `stwo-cairo-adapter`
- `stwo-cairo-prover`
- `stwo-cairo-serialize`
- `stwo-cairo-common`
- `cairo-air`
- `stwo_cairo_verifier`

Ce que fait chaque grande brique :

- `adapter` : transforme l'execution Cairo (`CairoRunner`) en `ProverInput`
- `prover` : genere la preuve Cairo basee sur Stwo
- `serialize` : gere les formats de preuve
- `common` / `cairo-air` : structures et contraintes Cairo-specifiques
- `stwo_cairo_verifier` : programme Cairo capable de verifier une preuve Stwo

Ce que `stwo-cairo` ne fait plus en priorite :

- il n'est plus le repo CLI utilisateur principal pour "prouver un programme Cairo" de facon pratique
- ce role a ete deplace vers `proving-utils`

Quand l'utiliser :

- pour les integrations Rust bas niveau autour du proving Cairo
- pour manipuler directement `ProverInput`, preuve, verification

Mise en fonctionnement typique :

1. recuperer un `CairoRunner`
2. appeler l'adapter
3. obtenir un `ProverInput`
4. appeler le prover Cairo
5. eventuellement verifier ou serialiser la preuve

Sorties typiques :

- `ProverInput`
- preuve Stwo Cairo
- preuve serialisee en JSON ou format CairoSerde

---

### 2.6 `stwo-circuits`

Repo : `starkware-libs/stwo-circuits`

Role principal :

- circuits de verification
- verification circuitifiee
- recursion

Ce que fait `stwo-circuits` :

- construit des circuits qui representent une verification de preuve
- permet de prouver qu'une autre preuve a bien ete verifiee
- sert de brique importante pour la recursion

Crates visibles dans le workspace :

- `circuit-cairo-air`
- `circuit-air`
- `circuit-common`
- `circuit-prover`
- `circuits`
- `circuits-stark-verifier`

Ce que `stwo-circuits` ne fait pas dans le pipeline standard :

- il n'est pas la brique standard qui prend directement un programme Cairo compile pour l'executer et produire sa premiere preuve

Quand l'utiliser :

- quand on veut representer la verification dans un circuit
- quand on veut construire une preuve recursive
- quand on veut "prouver la verification d'une preuve precedente"

Sorties typiques :

- preuve de circuit
- structures intermediaires de verification recursive

---

### 2.7 `proving-utils`

Repo : `starkware-libs/proving-utils`

Role principal :

- orchestrateur pratique en Rust / CLI pour les workflows Cairo -> preuve Stwo

Ce que contient principalement `proving-utils` :

- `cairo-program-runner`
- `cairo-program-runner-lib`
- `stwo-vm-runner`
- `stwo-run-and-prove`
- `privacy_prove`
- `privacy_circuit_verify`

Ce que fait `proving-utils` :

- execute un programme Cairo compile avec les bons reglages
- produit des artefacts d'execution
- adapte le resultat a `ProverInput`
- appelle le prover Stwo/Cairo
- peut verifier la preuve
- expose des workflows plus specialises autour de privacy et recursion

Ce que `proving-utils` ne remplace pas :

- il ne remplace ni le compilateur Cairo, ni `cairo-vm`, ni `stwo-cairo`, ni `stwo-circuits`
- il s'appuie sur eux

Quand l'utiliser :

- quand on veut une interface CLI concrete pour executer, preparer, prouver, verifier
- quand on veut centraliser un pipeline de proving sans reprogrammer toute la glue

Mise en fonctionnement typique :

- avec `cairo-program-runner` :
  - execution simple ou en `proof_mode`
  - generation de trace, memory, AIR public/private inputs, PIE

- avec `stwo-vm-runner` :
  - execution du programme
  - adaptation en `ProverInput`
  - export du `ProverInput` et des `ExecutionResources`

- avec `stwo-run-and-prove` :
  - execution
  - adaptation
  - preuve
  - verification optionnelle
  - export du proof file et de donnees de debug

Sorties typiques :

- output JSON
- execution resources JSON
- Cairo PIE
- AIR public/private input JSON
- trace / memory binaires
- `ProverInput` JSON
- preuve JSON ou CairoSerde

---

### 2.8 `cairo_native`

Repo : `starkware-libs/cairo_native`

Role principal :

- compilation de Sierra vers code machine natif via MLIR/LLVM

Ce qu'il fait :

- acceleration de l'execution
- execution native plutot que via la VM classique

Ce qu'il ne fait pas :

- ce n'est pas la brique centrale du pipeline de preuve Stwo

Quand l'utiliser :

- quand l'objectif est la performance d'execution, pas le pipeline standard de proving

---

## 3. Dependances entre les outils

Cette section decrit les dependances logiques, pas seulement les dependances Cargo.

### 3.1 Dependances de haut niveau

- `proving-utils` depend fonctionnellement de :
  - `cairo-vm`
  - `stwo-cairo`
  - parfois `stwo-circuits`
  - plus generalement de la disponibilite d'un programme compile produit grace a `cairo`

- `stwo-cairo` depend conceptuellement de :
  - `cairo-vm` pour les donnees d'execution Cairo
  - `stwo` pour les primitives du prover/verifier STARK

- `stwo-circuits` depend conceptuellement de :
  - `stwo`
  - de composants Cairo-specifiques quand on veut verifier une preuve Cairo
  - souvent d'artefacts issus de `stwo-cairo`

- `cairo-vm` depend du fait qu'un programme Cairo ait deja ete compile

### 3.2 Chaine de dependance "pipeline standard"

La chaine standard ressemble a ceci :

1. `cairo` produit un programme compile
2. `cairo-vm` execute ce programme compile
3. `stwo-cairo-adapter` transforme l'execution en `ProverInput`
4. `stwo-cairo-prover` genere une preuve
5. `stwo_cairo_verifier` ou la couche de verification associee verifie cette preuve
6. `stwo-circuits` intervient si on veut prouver cette verification dans un circuit
7. `proving-utils` peut piloter plusieurs de ces etapes

### 3.3 Dependances detaillees par composant

#### `cairo-program-runner`

Depend de :

- `cairo-program-runner-lib`
- `cairo-vm`

Produit :

- outputs
- resources
- PIE
- AIR public/private inputs
- trace/memory

#### `stwo-vm-runner`

Depend de :

- `cairo-program-runner-lib`
- `cairo-vm`
- `stwo-cairo-adapter`

Produit :

- `ProverInput`
- `ExecutionResources`

#### `stwo-run-and-prove`

Depend de :

- `cairo-program-runner-lib`
- `cairo-vm`
- `stwo-cairo-adapter`
- `stwo-cairo-prover`
- format de serialisation de `stwo-cairo`

Produit :

- preuve
- output programme optionnel
- debug data (`ProverInput`)

#### `privacy_prove`

Depend de :

- `cairo-program-runner-lib`
- `cairo-vm`
- `stwo-cairo`
- `stwo-circuits`
- `privacy-circuit-verify`

Produit :

- preuve "privacy" compressee
- output preimage
- eventuellement preuve recursive

#### `privacy_circuit_verify`

Depend de :

- `stwo-circuits`
- `stwo-cairo`
- programme de bootloader privacy embarque

Produit :

- verification d'une preuve privacy / recursive

---

## 4. Pipeline complet sans recursion

Voici le pipeline "normal" pour un programme Cairo que l'on veut prouver.

### Etape 1 : ecriture du programme

Entree :

- fichier source `.cairo`

Outil principal :

- `cairo`

Sortie :

- programme compile
- selon le flux : Sierra, CASM, executable, JSON compile

### Etape 2 : execution prouvable

Entree :

- programme compile
- inputs utilisateur

Outil principal :

- `cairo-vm`
- ou `proving-utils` via `cairo-program-runner`

Sortie possible :

- output programme
- execution resources
- trace
- memory
- AIR public input
- AIR private input
- PIE

### Etape 3 : adaptation au prover

Entree :

- execution Cairo terminee (`CairoRunner`)

Outil principal :

- `stwo-cairo-adapter`
- ou `proving-utils` via `stwo-vm-runner` / `stwo-run-and-prove`

Sortie :

- `ProverInput`

### Etape 4 : proving

Entree :

- `ProverInput`

Outil principal :

- `stwo-cairo-prover`
- ou `proving-utils` via `stwo-run-and-prove`

Sortie :

- preuve Stwo/Cairo
- format JSON ou CairoSerde selon la configuration

### Etape 5 : verification simple

Entree :

- preuve
- enonce public necessaire a la verification

Outil principal :

- verification dans l'ecosysteme `stwo-cairo`
- eventuellement programme verifier Cairo (`stwo_cairo_verifier`)

Sortie :

- succes / echec de verification

---

## 5. Pipeline complet avec recursion

La recursion signifie ici :

- on ne se contente pas de verifier la preuve initiale
- on construit une nouvelle preuve affirmant que la verification de la preuve precedente s'est bien passee

### Etape 1 : preuve initiale

Pipeline identique a la section precedente :

- programme source Cairo
- compilation
- execution
- adaptation
- preuve initiale

Sortie :

- `proof_1`

### Etape 2 : verification circuitifiee

Entree :

- `proof_1`
- donnees publiques necessaires a sa verification

Outils principaux :

- `stwo-circuits`
- composants de verification Cairo specialises

But :

- encoder la verification de `proof_1` dans un circuit

Sortie :

- circuit / contexte / donnees pretraitees / trace de circuit selon l'implementation

### Etape 3 : preuve recursive

Entree :

- circuit de verification de `proof_1`

Outils principaux :

- `stwo-circuits`
- eventuellement workflows specialises de `proving-utils` comme `privacy_prove`

Sortie :

- `proof_2`

Interpretation de `proof_2` :

- `proof_2` atteste que `proof_1` a ete correctement verifiee

Si on pousse encore plus loin :

- on peut iterer pour agreger ou compresser plusieurs niveaux de preuve

---

## 6. Quels outils peuvent etre diriges directement via `proving-utils`

Dans le schema global, `proving-utils` ne pilote pas tout. Il ne remplace pas la compilation initiale de `cairo`, et il ne remplace pas non plus toutes les briques de `stwo-circuits`.

En revanche, il peut piloter directement plusieurs etapes critiques.

### Directement pilotables via `proving-utils`

- execution simple de programme compile
  - via `cairo-program-runner`

- execution en `proof_mode`
  - via `cairo-program-runner`

- generation de :
  - outputs
  - execution resources
  - Cairo PIE
  - AIR public/private inputs
  - trace
  - memory

- transformation en `ProverInput`
  - via `stwo-vm-runner`

- proving complet
  - via `stwo-run-and-prove`

- verification optionnelle de la preuve generee
  - via `stwo-run-and-prove`

- certains workflows specialises privacy / recursive
  - via `privacy_prove`
  - via `privacy_circuit_verify`

### Non directement remplaces par `proving-utils`

- compilation source Cairo initiale
  - releve de `cairo` / Scarb

- construction generale des circuits de recursion
  - releve de `stwo-circuits`

- developpement interne du prover Stwo
  - releve de `stwo`

---

## 7. Schema du pipeline complet

Le schema ci-dessous montre :

- les etapes du pipeline
- les formats de sortie
- les dependances
- les points pilotables par `proving-utils`

```text
  [Code source Cairo]
          |
          |  ecriture / compilation
          v
  +------------------+
  |      cairo       |
  |   (toolchain)    |
  +------------------+
          |
          | sort selon le flux :
          | - Sierra
          | - CASM
          | - executable
          | - programme compile JSON
          v
  [Programme compile]
          |
          | execution avec inputs
          |-------------------------------\
          |                                \
          v                                 \
  +------------------+                       \
  |     cairo-vm     |                        \
  |  execution VM    |                         \
  +------------------+                          \
          |                                      \
          | sorties possibles :                   \
          | - output JSON                          \
          | - execution_resources JSON             |
          | - trace.bin                            |
          | - memory.bin                           |
          | - air_public_input.json                |
          | - air_private_input.json               |
          | - cairo_pie.zip                        |
          v                                       |
  [Execution Cairo / CairoRunner]                 |
          |                                       |
          | adaptation                            |
          v                                       |
  +--------------------------+                    |
  |    stwo-cairo-adapter    |                    |
  +--------------------------+                    |
          |                                       |
          | sortie : ProverInput                  |
          v                                       |
  [ProverInput]                                   |
          |                                       |
          | proving                               |
          v                                       |
  +--------------------------+                    |
  |    stwo-cairo-prover     |                    |
  +--------------------------+                    |
          |                                       |
          | sortie : proof.json / proof.serde     |
          v                                       |
  [Preuve initiale]                               |
          |                                       |
          | verification simple                   |
          v                                       |
  +-----------------------------+                 |
  | stwo-cairo verifier layer   |                 |
  | / stwo_cairo_verifier       |                 |
  +-----------------------------+                 |
          |                                       |
          | verification OK/KO                    |
          v                                       |
  [Preuve verifiee]                               |
                                                  |
--------------------- branche recursion ----------|
                                                  |
  [Preuve initiale + enonce public]               |
          |                                       |
          | verification encodee en circuit       |
          v                                       |
  +------------------+                            |
  |  stwo-circuits   |                            |
  |  circuit layer   |                            |
  +------------------+                            |
          |                                       |
          | sortie intermediaire :                |
          | - circuit context                     |
          | - preprocessed circuit                |
          | - circuit proof inputs                |
          v                                       |
  [Circuit de verification]                       |
          |                                       |
          | proving recursive                     |
          v                                       |
  +------------------+                            |
  |  stwo-circuits   |                            |
  | recursive proof  |                            |
  +------------------+                            |
          |                                       |
          | sortie : recursive proof              |
          v                                       |
  [Preuve recursive]                              |


Points pilotables directement via proving-utils :

  [Programme compile]
      |
      +--> proving-utils / cairo-program-runner
      |      -> output JSON
      |      -> execution_resources JSON
      |      -> trace.bin
      |      -> memory.bin
      |      -> air_public_input.json
      |      -> air_private_input.json
      |      -> cairo_pie.zip
      |
      +--> proving-utils / stwo-vm-runner
      |      -> ProverInput JSON
      |      -> ExecutionResources JSON
      |
      +--> proving-utils / stwo-run-and-prove
      |      -> proof.json / proof.serde
      |      -> verification optionnelle
      |      -> debug prover_input.json
      |
      +--> proving-utils / privacy_prove
      |      -> privacy proof
      |      -> output preimage
      |
      +--> proving-utils / privacy_circuit_verify
             -> verification privacy / recursive
```

---

## 8. Resume pratique : qui fait quoi

### Si tu veux seulement compiler

Utilise :

- `cairo`

### Si tu veux executer un programme compile

Utilise :

- `cairo-vm`
- ou `proving-utils` / `cairo-program-runner`

### Si tu veux generer trace / memory / AIR inputs / PIE

Utilise :

- `cairo-vm`
- ou plus pratiquement `proving-utils` / `cairo-program-runner`

### Si tu veux construire un `ProverInput`

Utilise :

- `stwo-cairo-adapter`
- ou `proving-utils` / `stwo-vm-runner`

### Si tu veux generer une preuve Stwo d'un programme Cairo

Utilise :

- `stwo-cairo-prover`
- ou plus simplement `proving-utils` / `stwo-run-and-prove`

### Si tu veux verifier une preuve simple

Utilise :

- la couche de verification `stwo-cairo`
- eventuellement `stwo_cairo_verifier`

### Si tu veux faire de la recursion

Utilise :

- `stwo-circuits`
- et selon le workflow, certaines crates specialisees de `proving-utils`

---

## 9. Erreurs de conception frequentes

### Erreur 1 : croire que `stwo-circuits` execute directement le programme Cairo standard

Faux dans le pipeline normal.

Le programme Cairo est d'abord execute via `cairo-vm`, pas par `stwo-circuits`.

### Erreur 2 : croire que `proving-utils` remplace `cairo`

Faux.

`proving-utils` ne remplace pas la phase initiale de compilation du langage.

### Erreur 3 : croire que `stwo` suffit seul pour prouver un programme Cairo

Faux.

`stwo` est generique. La specialisation Cairo passe par `stwo-cairo`.

### Erreur 4 : confondre verification simple et recursion

La verification simple valide une preuve existante.

La recursion construit une nouvelle preuve attestant qu'une verification precedente s'est bien deroulee.

---

## 10. Resume final

Le pipeline conceptuel correct est :

1. `cairo` compile le programme source
2. `cairo-vm` execute le programme compile
3. `stwo-cairo-adapter` convertit l'execution en `ProverInput`
4. `stwo-cairo-prover` genere la preuve
5. la couche de verification `stwo-cairo` verifie cette preuve
6. `stwo-circuits` intervient pour representer cette verification dans un circuit et produire une preuve recursive
7. `proving-utils` peut piloter directement plusieurs etapes intermediaires et pratiques de ce pipeline

En une phrase :

`proving-utils` est la glue operationnelle ; `cairo` compile ; `cairo-vm` execute ; `stwo-cairo` prouve et verifie pour Cairo ; `stwo-circuits` sert surtout a la recursion.
