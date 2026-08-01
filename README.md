# Databricks Workspace Migration Toolkit

Bulk-migrate the **workspace-file layer** (notebooks, workspace files, Lakeview dashboards `.lvdash.json`, SQL alerts `.dbalert.json`, and saved Unified SQL queries `.dbquery.ipynb`) from one Databricks workspace to another using **Git folders** and standard Git CLI.

Queries (`.dbquery.ipynb`) are **not** supported by the Workspace `export`/`import` APIs and do not appear in `workspace list`. The only supported programmatic path that carries them — together with dashboards and notebooks — is the **Git integration**. This toolkit packages that flow so you fill in a config once and run one command per phase.

> Full step-by-step detail, background, and troubleshooting live in the **[Wiki](../../wiki)**. This README is the quick start.

---

## What it does

```text
source normal folder(s)
  -> programmatic WSFS copy into a Git worktree
  -> git add / commit / push  (main)
remote Git repository
  -> git clone in destination workspace
  -> land each folder at its original path
```

- **Multi-folder by design** — define one or many folders in `folders.tsv`; a single run migrates them all.
- **Config-driven** — every variable lives in `config.env`; the scripts fail fast if anything is missing, so a recycled web terminal is never a problem.
- **Ephemeral credentials** — temporary CLI profiles and Git credentials are minted per run and torn down automatically, with no collision with your existing profiles/credentials.

---

## Repository layout

```text
.
├── README.md                          # this file
├── bootstrap_migration_toolkit.sh     # one-paste self-extractor for web terminals
└── migration/
    ├── config.env.example             # copy to config.env and fill in
    ├── folders.tsv                    # one row per folder to migrate
    ├── lib/
    │   ├── common.sh                  # config loader + helpers (copy_tree, guards)
    │   ├── ephemeral.sh               # ephemeral profile/credential lifecycle
    │   └── validate_copy.py           # validates file set + byte sizes after each copy
    └── bin/
        ├── 10_local_setup.sh          # LOCAL: auth both workspaces, mint Git credentials
        ├── 20_source_package.sh       # SOURCE web terminal: copy -> commit -> push
        ├── 30_dest_clone.sh           # DEST web terminal: clone + verify
        └── 40_dest_land.sh            # DEST web terminal: land folders at original paths
```

---

## Prerequisites

- A remote Git repository reachable from both workspaces, with an initial commit on `main`.
- A Git provider PAT with repository read/write permission.
- Git CLI support enabled in both workspaces (admin, one-time).
- Databricks CLI `0.205.0+` installed on your laptop.
- Unified SQL queries **saved** (not drafts) before migration.
- Repository within the current Git CLI file-count limit (Databricks documents 10,000 files for automatic Git CLI access).

---

## Quick start

### 0. Get the toolkit

Clone this repo on your laptop, **or** paste `bootstrap_migration_toolkit.sh` into a Databricks web terminal to self-extract the `migration/` folder there.

### 1. Configure once

```bash
cp migration/config.env.example migration/config.env
# Edit migration/config.env: workspace URLs, repo URL, staging paths.
# Then list your folders (one per line, TAB-separated):
#   <source folder>   <path inside repo>   [optional destination path]
$EDITOR migration/folders.tsv
```

### 2. Phase 1 — Local setup (laptop terminal)

```bash
bash migration/bin/10_local_setup.sh
```

Authenticates against both workspaces with ephemeral profiles, mints the ephemeral Git credentials, and writes `RUN_ID` + credential ids back into `config.env`.

> After this step, **re-copy the updated `config.env`** into the web terminals before Phases 2 and 3.

### 3. Phase 2 — Package the source (source web terminal)

```bash
bash migration/bin/20_source_package.sh
```

Copies every folder from `folders.tsv` into the Git worktree, validates counts/bytes, commits, and pushes to `main`. Tears down the source Git credential on success.

### 4. Phase 3 — Clone in the destination (destination web terminal)

```bash
bash migration/bin/30_dest_clone.sh
```

Clones the repo and verifies every migrated folder is present. Tears down the destination Git credential once the clone is verified.

### 5. Phase 4 — Land at original paths (destination web terminal)

```bash
bash migration/bin/40_dest_land.sh
```

Places each folder at its original absolute path in the destination so existing references resolve. Pure WSFS copy — no Git credential needed.

### 6. Post-migration

Open each `.dbquery.ipynb` and dashboard in the destination and **repoint the SQL warehouse** — warehouse IDs and other environment-specific metadata do not travel with the files.

---

## Key rules learned the hard way

- **Everything stays on `main`.** Extra migration branches caused clone/push failures; only use a branch + PR if `main` has branch protection.
- **Save queries first.** Draft `.dbquery.ipynb` files have no persisted content and land empty.
- **Web terminals are ephemeral.** Variables live only in the current shell; the scripts reload `config.env` so a restart is safe — just re-run the phase.
- **Path preservation is a destination concern only.** The source folder is never moved or modified.
- **Delete credentials strictly by captured id.** The toolkit never deletes "the GitHub one" in bulk, so your existing credentials are untouched.

---

## Security

- `migration/config.env` holds workspace URLs and credential ids — keep it out of version control (see `.gitignore`). Commit only `config.env.example`.
- PATs are never echoed or stored in the repo; ephemeral Git credentials are torn down automatically per run.

---

## Documentation

See the **[Wiki](../../wiki)** for the full runbook: architecture, per-command explanations, scaling guidance, cutover/rollback, and troubleshooting (auth, EMU/SSO, Git CLI limits, empty queries, path nesting).
