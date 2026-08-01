---
name: ship-pr
description: Commit the current branch's changes, rebase onto the remote's default branch, run the repo's CI checks locally (re-read fresh from its CI workflow file each time, matching its exact command scope and toolchain version) to catch failures before GitHub does, then push and open a PR - watching the real CI run through to green. Use whenever the user asks to commit and open a PR, "ship this", "push and make a PR", "rebase and open a PR", wants a branch validated against CI before pushing, or reports a CI failure and wants a fix-and-repush cycle. Also fires on terse "commit, rebase, pass tests, push, PR" style requests.
---

# Ship a PR

Takes a branch from "has some changes" to "open PR with green CI", the way a
careful engineer would: verify locally with the *exact* commands CI runs,
not an approximation of them, before ever pushing. The whole point of this
skill is closing the gap between "passes on my machine" and "passes in CI" -
most of its steps exist because that gap is where PRs actually go wrong.
Encodes lessons from doing this for real on `quantpack-factors`, including
one it caught the hard way (see step 3) - follow it instead of re-deriving
the process from scratch each time.

## 0. Orient before touching anything

- `git status` and `git diff` (staged + unstaged) - know what's actually
  changing before staging any of it. If something looks unrelated to the
  current task, or touches a file that might hold secrets (`.env`,
  credentials, anything with an odd name for its content), flag it to the
  user rather than silently including it.
- `git branch --show-current`, and find the repo's default branch:
  `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`
  (falls back to `git remote show origin | sed -n 's/.*HEAD branch: //p'` if
  that ref isn't set locally). If the current branch *is* the default
  branch, stop and ask the user what branch to work on instead - this skill
  commits and pushes, and doing that straight to the default branch is a
  different, much higher-stakes action than opening a PR, and shouldn't
  happen by default.
- Identify the PR remote with `git remote -v`. Most repos only have
  `origin`, but some (e.g. `quantpack-factors`) have several - a Bitbucket
  mirror, a local sync remote for another tool, etc. GitHub is normally the
  one PRs go through, but don't assume: if more than one remote looks
  plausible, ask which one rather than guessing.

## 1. Commit

Stage specific files (never `git add -A`/`git add .`) and write a commit
message that explains *why*, matching the repo's existing log style (`git
log --oneline` for recent examples). Follow the standard git safety rules:
new commits over amends, no `--no-verify`, no force-push, ever - unless the
user explicitly asks for one of those in this exact request.

If there's nothing to commit (working tree already clean, e.g. the user
just wants an already-committed branch rebased/verified/pushed), that's
fine - skip straight to rebasing.

## 2. Rebase onto the remote's default branch

```
git fetch <remote>
git rebase <remote>/<default-branch>
```

If this produces conflicts, **stop and surface them** - show the user which
files conflict and why, rather than resolving them yourself. Conflict
resolution needs judgment about which side is actually correct that isn't
safe to guess at.

## 3. Verify locally with CI's exact commands - not a remembered version of them

This is the step that earns its keep. Re-read the CI workflow file(s) fresh
every time (`.github/workflows/*.yml`, or the repo's equivalent for its CI
provider) instead of relying on what it said last time you looked, or on
what another repo's CI looked like. CI configs drift, and a stale mental
model of "what CI runs" is exactly how a locally-green branch turns red on
GitHub.

For each job that runs on pull requests, replicate its steps **in order,
with the exact same scope arguments** - a command run against a narrower
scope than CI uses can pass locally while CI's wider scope fails silently
different. This already happened for real on `quantpack-factors`: running
`mypy src` locally passed, but its CI job runs `mypy src tests`, and caught
a type error that only existed in a test file (a `Protocol` method's
parameter type was narrower than the protocol declared - a contravariance
violation invisible outside `tests/`). Copy each command verbatim out of
the workflow file, don't paraphrase or shorten it.

Match the toolchain version too, not just the commands - if CI pins a
specific language/tool version (e.g. `uv python install 3.11`, a pinned
Node version, etc.) and it differs from whatever the ambient default
resolves to locally, install and use that pinned version explicitly rather
than trusting the default. Version drift is a less common cause of
local-pass/CI-fail than scope drift, but it's real and cheap to rule out.

**Sandbox notes**, if running inside a Claude Code sandbox with restricted
filesystem writes - these aren't part of what CI does, they're just what it
takes to run some toolchains here at all:
- For `uv`-based Python repos: `~/.cache/uv` is often not writable. Set
  `UV_CACHE_DIR` to a scratch-writable directory before any `uv` command,
  e.g. `export UV_CACHE_DIR="$TMPDIR/uv-cache"`. If installing a pinned
  Python version fails against the default install directory, set
  `UV_PYTHON_INSTALL_DIR` to a scratch-writable directory too (e.g.
  `"$TMPDIR/uv-python"`) and retry.
- Other package managers/toolchains can hit the analogous "default cache
  dir isn't writable" issue - the fix is the same shape: point its cache/
  install-dir env var at a scratch-writable location instead of fighting
  the sandbox.

## 4. If anything in step 3 fails: stop

Do not push. Do not open a PR. Report:
- the exact command that failed (verbatim, not summarized),
- its real error output (verbatim - the actual traceback/diagnostic, not a
  paraphrase of it, since the fix needs to address the real cause), and
- your read on the root cause if you have one.

Once the underlying issue is fixed (by you or the user, in the main
conversation - this skill doesn't blindly retry or auto-patch), commit the
fix as a new commit, then **re-run every check in step 3 from the top**,
not just the one that failed. A fix for one check can easily regress
another (e.g. a lint autofix that changes behavior, or a type-annotation
change that breaks a test's assumptions) - only push once all of them pass
together on the current commit.

## 5. Push

```
git push -u <remote> <branch>
```

In a multi-worktree sandbox setup, this can print `fatal: failed to store`
or a config-lock error while still succeeding - those come from trying (and
failing, due to sandbox permissions) to write shared `.git/config`/upstream-
tracking metadata across sibling worktrees, not from the push itself
failing. Don't trust the exit noise alone either way: confirm the push
actually landed by checking `git ls-remote <remote> <branch>`'s commit hash
against `git rev-parse HEAD` - if they match, the push succeeded regardless
of what else printed. If the `-u` push reports an upstream-tracking error
specifically, a plain `git push <remote> <branch>` (without `-u`) achieves
the same real result without needing that local config write.

## 6. Open the PR

```
gh pr create --repo <owner>/<repo> --base <default-branch> --head <branch> \
  --title "..." --body "..."
```

Body format: a `## Summary` (bullet points, what changed and why) and a
`## Test plan` (checklist - what was actually verified, referencing the
real commands/results from step 3, not a generic "tests pass"). Keep the
title under ~70 characters; put detail in the body.

## 7. Watch the real CI run, don't assume local success implies it

Local verification matches CI's commands and toolchain version, but still
runs on a different OS/runner and can hit things local reproduction can't
(cache service hiccups, a dependency that resolves differently, etc.).
After opening the PR:

```
gh pr checks <pr-number> --repo <owner>/<repo>
```

If it's still running, `gh run watch <run-id> --repo <owner>/<repo>
--exit-status` to follow it to completion rather than declaring victory
early. Report the final PR URL and the actual CI outcome - if it somehow
still fails despite local verification passing, that's a real finding
worth surfacing (diagnose it the same way as step 4: exact command, exact
error, real root cause), not something to paper over.
