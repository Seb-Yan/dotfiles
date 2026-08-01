---
name: setup-dev-trunk
description: Set up a personal long-lived branch as your working trunk in a repo whose real default branch (e.g. main) you don't control and don't want to open PRs against or commit to directly. Creates/confirms the branch, sets up a uv-managed Python environment (pyproject.toml + uv.lock derived from actual code imports, not a blind pip-freeze dump) if the repo is Python and doesn't have one yet, commits and pushes the branch, and repoints local origin/HEAD so treehouse/twget worktree pools default to checking out this branch instead of the real default branch. Use when the user wants to treat their own branch as "main"/trunk for local development with treehouse or twget, says things like "set up my dev branch as main", "make twget use my branch instead of main", "I don't want to PR to the real main", "treat this branch as trunk", or is otherwise configuring a repo they don't control for a treehouse/twget-based workflow.
---

# Set up a personal dev branch as your trunk (treehouse/twget + uv)

For a repo where someone else owns the real default branch and you don't
want to PR or commit to it, this sets up your own long-lived branch as the
one you actually work against: feature branches fork from it and merge back
into it, never into the real default branch. It also makes `treehouse`/
`twget` worktree pools land on your branch automatically instead of the real
default branch, and (if the repo is Python) gets `uv` set up so `uv sync`
is all a fresh worktree ever needs.

This encodes lessons learned setting this up for real on `data05-inspect-dna`
- follow it instead of re-deriving from scratch. Several steps below only
exist because a naive version fails, especially around sandboxed agents and
`git worktree`/`treehouse` internals that aren't documented anywhere public.

## Usage

`/setup-dev-trunk [branch-name]`

- If `branch-name` is omitted, ask the user what to call it. This is a pure
  naming preference with no correct default - don't guess, and don't just
  reuse the repo name or your own username without asking.
- Assumes the current directory is the target repo and its primary remote
  is named `origin`. Each step below is safe to skip if already done, so
  this is fine to run on a repo that's already partway through this setup
  (e.g. branch exists and is pushed, just needs `origin/HEAD` repointed).

## Steps

1. **Check for uncommitted work first.** Run `git status`. If there's
   anything present that isn't yours from this task, stash it (`git stash
   -u`) rather than switching branches over it - don't lose someone's
   in-progress work over a branch setup task.

2. **Create or confirm the branch.** If `branch-name` doesn't exist yet,
   `git checkout -b <branch-name>`. If the user is already on it, or it
   already exists, just confirm and move on - don't recreate it.

3. **Set up `uv` if this is a Python repo without one already.** Skip this
   entire step if `pyproject.toml` + `uv.lock` already exist - just confirm
   `.venv/` is gitignored and that `pyproject.toml`/`uv.lock` are NOT
   gitignored (both are common to already be right; only fix if wrong).

   Otherwise:
   - **Derive direct dependencies by scanning actual usage, don't dump a
     `pip freeze`.** An existing `requirements.txt` (or similar) is
     typically a full transitive freeze - most of it transitive, some of it
     dead/unused. Instead, walk every `.py` and `.ipynb` file and collect
     top-level `import X` / `from X import ...` names. For notebooks, parse
     the JSON and pull `source` lines out of code cells; a plain text grep
     will miss them. Watch for comma-separated imports on one line
     (`import os, requests, ipykernel`) - split on commas, a regex matching
     only the first name after `import` silently drops the rest.
   - **Some dependencies never show up as an `import` line** - they're
     pulled in by pandas/other libraries as an optional backend. Grep for
     these signals too: `read_excel`/`to_excel` or `ExcelWriter` ->
     `openpyxl` (default xlsx read engine) and/or `xlsxwriter` (if
     `engine="xlsxwriter"` appears); `read_parquet`/`to_parquet` ->
     `pyarrow`; `fetch_pandas_all()` on a Snowflake cursor ->
     `snowflake-connector-python[pandas]` (the `[pandas]` extra matters,
     it's what pulls the Arrow-based fetch path in).
   - **Cross-check every hit against an existing lockfile/freeze file** if
     one exists, both to get realistic version floors (e.g.
     `pandas>=2.2`, not an exact pin - exact pins belong in `uv.lock`, not
     `pyproject.toml`) and to catch import-name-vs-PyPI-name mismatches
     (`sklearn` -> `scikit-learn`, `snowflake` -> `snowflake-connector-python`).
   - **Drop anything mentioned only in a commented-out line, or never
     mentioned anywhere in code at all**, even if it's pinned in the old
     freeze file - a freeze file accumulates dead pins over time. Also drop
     platform-specific packages that don't apply on the current OS (e.g.
     `pywinpty`, `pywin32-ctypes` are Windows-only and will fail to build
     from source on macOS/Linux if listed as a direct dependency - they're
     already pulled in transitively on Windows via markers on packages like
     `terminado`, so they don't need to be listed at all).
   - **Decide whether the repo is actually an installable package.** If
     tracked code does bare imports like `import qc_assets` rather than
     `from src.qc import qc_assets`, the `src/` layout (even with
     `__init__.py` files) isn't really wired up as an installed package -
     it's consumed via `sys.path`/notebook-cwd tricks instead. In that case
     set `[tool.uv] package = false` in `pyproject.toml` and skip
     `[build-system]` entirely, rather than forcing a `hatchling` wheel
     config that doesn't match how the code is actually used.
   - Write `pyproject.toml`, then:
     ```
     export UV_CACHE_DIR="$TMPDIR/uv-cache"   # only needed if ~/.cache/uv isn't writable (sandboxed agent)
     uv lock
     rm -rf .venv && uv sync
     ```
   - If the repo is notebook-heavy, register a kernel scoped to the venv
     itself, not the user's home directory:
     ```
     python -m ipykernel install --sys-prefix --name <repo> --display-name "<repo> (.venv)"
     ```
     Use `--sys-prefix`, not `--user` - a sandboxed agent typically can't
     write to `~/Library/Jupyter` (or platform equivalent), but
     `--sys-prefix` installs inside `.venv/share/jupyter/kernels/` instead,
     which is always writable since you just created `.venv` yourself.
   - If a live Jupyter server won't actually bind a port in your
     environment (`PermissionError` on `sock.bind`), that's a sandbox
     network restriction, not a real problem with the setup - the import
     checks and kernel registration are what actually matter here.

4. **Commit** `pyproject.toml`/`uv.lock` (and anything else from step 3) on
   the branch. Don't commit unless step 3 actually produced changes.

5. **Push the branch - ask for confirmation first.** `git push -u origin
   <branch-name>`. This step is not optional if you want `treehouse`/
   `twget` to work: its worktree pool builds new worktrees by fetching from
   `origin` and checking out whatever `refs/remotes/origin/HEAD` resolves
   to. A purely local branch is invisible to that fetch, so a fresh
   worktree falls back to the real default branch (stale, without whatever
   you just set up) instead of yours. Confirm before pushing since it's a
   remote-visible action - skip asking only if the user's original request
   already explicitly said to push.

6. **Point local `origin/HEAD` at the branch**, so future new
   `treehouse`/`twget` worktrees default to checking it out:
   ```
   git remote set-head origin <branch-name>
   ```
   This is safe to just do, without an extra confirmation round - it's a
   local-only git config change, not a push, and trivially reversible. But
   explain to the user what it does and how to undo it, because it's easy
   to mistake for something that touches the shared repo:
   - It does **not** change GitHub's actual configured default branch, and
     does **not** affect any other collaborator's clone - it only updates
     *this machine's* cached symref for "what origin considers its default
     branch." Revert with `git remote set-head origin -a` (needs network,
     re-detects from the remote) or `git remote set-head origin main` (or
     whatever the real default branch is, offline).
   - It only needs `refs/remotes/origin/<branch-name>` to already exist
     locally, which it will right after step 5's push - so skip passing
     `-a` here (that forces a live fetch, which can fail in a sandboxed
     agent with no SSH access: `git fetch origin: nc: authentication method
     negotiation failed`. That's a sandbox limitation, not a real problem -
     hand the plain `git remote set-head origin <branch-name>` command to
     the user if a fetch attempt fails).
   - Every `treehouse` pool worktree for a repo shares the *same* `.git`
     directory as the primary clone (its `.git` file is just a pointer:
     `gitdir: <primary-repo>/.git/worktrees/<name>`) - not an independent
     mirror clone. So this needs to run exactly once, in the primary
     checkout; it takes effect for the whole pool immediately, including
     slots that already exist.
   - `treehouse.toml` has no config field for this at all - confirmed by
     running `treehouse init` in a scratch repo and reading the full
     generated template, which only has `max_trees` and `root`. Don't go
     looking for a `base_branch`-style setting there; it doesn't exist.
     `treehouse`'s binary itself references `refs/remotes/origin/HEAD`
     (found via `strings` on the binary) - that's the actual mechanism,
     and it's a plain git concept, not something `treehouse` invented.
   - **Worktree slots that are already leased out won't retroactively
     move** to the new branch - this only changes what *new* `get`/`twget`
     calls check out. If the user wants an existing stale slot fixed too,
     they need to return it (`treehouse return <path>` / `twreturn`) and
     lease a fresh one, or just `git checkout <branch-name>` inside it
     directly.
   - If renaming/changing branches elsewhere in this repo hits `error:
     could not lock config file .git/config: Operation not permitted`,
     that's the same sandboxed-agent restriction (writes to `.git/config`
     are blocked, but ref-level operations like a branch rename usually
     still succeed) - don't treat it as a full failure; check `git branch
     --show-current` to see whether the actual ref-level change went
     through, and hand any leftover `git config --unset ...` cleanup to the
     user if the harness can't run it.

7. **Explain the resulting workflow** to the user so they know what to
   expect going forward, since it's not obvious from the outside:
   - `twget`/`treehouse get` will now hand out worktrees already on
     `<branch-name>` with `pyproject.toml`/`uv.lock` present (since those
     are committed and pushed) - but `.venv` itself is never carried over,
     because it's gitignored and `git worktree` only ever touches tracked
     files.
   - So the first time any given pool *slot* gets used, one `uv sync`
     inside it is still required. After that, since `treehouse`'s pool
     reuses the same physical directory across future leases/returns
     rather than recreating it, that `.venv` just sits there for every
     future reuse of that slot - so this cost is paid at most once per
     slot, not once per `twget`.
   - Ordinary feature work from here on: branch off `<branch-name>`, merge
     back into `<branch-name>` locally, no PR against the real default
     branch needed unless the user decides to actually upstream something.

## Notes

- Nothing here requires the repo to be Python/`uv`-based - if it isn't,
  just skip step 3 entirely and still do the branch + push + `origin/HEAD`
  steps. The branch-as-trunk part of this workflow stands on its own.
- If there's no `origin` remote at all (a purely local repo), steps 5 and 6
  don't apply - say so and stop there; there's no worktree pool to point at
  anything.
- Don't force any of this through with `dangerouslyDisableSandbox` or
  similar if a sandboxed step fails. The pattern throughout is: try the
  real command, recognize the specific sandbox failure signature described
  above, and either fall back to a plain-git equivalent or hand the exact
  command to the user to run themselves outside the sandbox.
