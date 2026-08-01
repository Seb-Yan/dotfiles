---
name: setup-bitbucket-mirror
description: Add Bitbucket as a secondary remote for a repo whose primary remote is GitHub, keeping GitHub as the remote used for all PRs and branch pushes, with an on-demand script to sync GitHub's default branch to Bitbucket via a pull request. Use when the user wants to mirror/backup a GitHub repo to Bitbucket, or asks to set up Bitbucket the way it was done for quantpack.
---

# Set up a GitHub-primary, Bitbucket-mirror repo

Adds Bitbucket as a secondary remote that gets synced from GitHub on demand,
never automatically. GitHub stays authoritative for all PRs, branch pushes,
and review. This encodes lessons learned setting this up for real on
`quantpack` - follow it instead of re-deriving from scratch, several steps
below only exist because a naive version fails.

## Usage

`/setup-bitbucket-mirror <bitbucket-workspace>/<bitbucket-repo-slug>`

- If the argument is omitted, ask the user for the Bitbucket workspace and
  repo slug (or a full `https://bitbucket.org/...` clone URL).
- Assumes the current directory is the target git repo and its GitHub
  remote is named `origin`. If it isn't, ask which remote is primary and
  substitute it below.

## Steps

1. Confirm this is a git repo with a GitHub remote: `git remote -v`. If a
   `bitbucket` remote already exists, skip to step 4.
2. Determine the default branch:
   `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`
   (falls back to `git remote show origin | sed -n 's/.*HEAD branch: //p'`
   if that ref isn't set locally).
3. Add the remote: `git remote add bitbucket https://bitbucket.org/<workspace>/<repo-slug>.git`
4. Try to set `git config remote.pushDefault origin` so a bare `git push`
   never accidentally targets Bitbucket. **This often fails from a sandboxed
   agent** (`could not lock config file .git/config: Operation not
   permitted`) - if so, don't fight it, just hand the exact command to the
   user to run themselves.
5. Check `git config --get credential.helper`. This is what lets a
   Bitbucket token be entered once and then cached, instead of prompting on
   every push. If unset, recommend the platform default: `osxkeychain` on
   macOS, `manager` on Windows, `libsecret` (or `store` as a fallback) on
   Linux. Setting this also commonly hits the same `.git/config` write
   restriction as step 4 - same fallback applies.
6. Create `scripts/sync-bitbucket.sh` from the template below, substituting
   nothing (it derives the default branch and Bitbucket path at runtime).
   Then `chmod +x` it.
7. Relay this to the user as a one-time manual setup - don't attempt it
   yourself, it needs their Bitbucket account:
   - Bitbucket deprecated **App Passwords**; they need a Bitbucket **API
     token** instead, created at
     `https://id.atlassian.com/manage-profile/security/api-tokens` with
     repo write scope.
   - The first push will prompt for a username (their Atlassian account
     email) and password (the API token). After that, the credential
     helper from step 5 caches it and it won't prompt again.
   - If a stale App Password is already cached, pushes fail with an HTTP
     410 ("App passwords are deprecated") instead of a normal auth prompt,
     and it will keep failing silently since a 410 doesn't trigger git's
     usual erase-and-retry flow. Clear it with:
     `git credential reject` (fed `protocol=https` / `host=bitbucket.org`
     on stdin), or if that doesn't work, manually via the OS credential
     manager GUI (Keychain Access on macOS, search `bitbucket.org`).
     A sandboxed agent typically **cannot** do this step itself - it needs
     an interactive/GUI keychain session - so hand it to the user.
8. **If the Bitbucket repo is brand new and empty (no branches yet),
   seed its default branch before ever running the sync script:**
   `git push bitbucket refs/remotes/origin/<default-branch>:refs/heads/<default-branch>`.
   Bitbucket auto-designates whichever branch lands first in an empty repo
   as its "Main branch" setting. If the sync script's `sync/github-*`
   branch gets pushed first instead, Bitbucket adopts *that* as main, and
   the PR link the script prints (`dest=<default-branch>`) has no real
   branch to target - the PR page shows no merge target / can't merge.
   This direct push is safe only because the repo is empty (nothing to
   protect yet); it's a one-time bootstrap, not the general sync method.
   If the mis-selection already happened, fix it after seeding the branch:
   Bitbucket repo -> **Repository settings -> General -> Main branch**
   dropdown -> switch it to `<default-branch>` -> Save. That dropdown only
   lists branches that already exist on Bitbucket, so the direct push must
   happen first.
9. Have the user run `./scripts/sync-bitbucket.sh` once to confirm auth
   works end to end, since a sandboxed agent often can't complete
   interactive credential entry itself.
10. If creating the GitHub PR for these changes via `gh pr create` fails
   with a TLS/certificate error (`x509: ... OSStatus ...`), that's a
   sandbox limitation, not a real problem - `git push` still works. Hand
   the exact `gh pr create` command to the user, or give them the
   `https://github.com/<owner>/<repo>/pull/new/<branch>` URL.

## Script template (`scripts/sync-bitbucket.sh`)

Defaults to PR-based sync, not a direct push to the default branch.
**Don't try direct-push-to-master as the primary approach** - Bitbucket
branch permissions very commonly reject it outright
(`remote: Permission denied ... pre-receive hook declined`), even for
admins, with no way to detect this without trying it. A PR-based sync
works whether or not the branch is protected, so it's the safe default.

```bash
#!/usr/bin/env bash
# Sync GitHub's default branch to Bitbucket via a pull request.
#
# GitHub (origin) is the source of truth for all PRs and branch pushes.
# Push to a dedicated sync branch on Bitbucket instead of the protected
# branch directly, then merge a Bitbucket PR to actually land it - direct
# pushes are commonly rejected by branch permissions even for admins, and
# this works regardless of how strict that protection is. It's safe to
# force-push the sync branch since nothing else should ever be based on
# it - it only exists to mirror origin's default branch.
set -euo pipefail

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="$(git remote show origin | sed -n 's/.*HEAD branch: //p')"
fi
SYNC_BRANCH="sync/github-${DEFAULT_BRANCH}"

BITBUCKET_URL="$(git remote get-url bitbucket)"
BITBUCKET_PATH="${BITBUCKET_URL#*bitbucket.org/}"
BITBUCKET_PATH="${BITBUCKET_PATH%.git}"

git fetch origin "${DEFAULT_BRANCH}"
git push --force bitbucket "refs/remotes/origin/${DEFAULT_BRANCH}:refs/heads/${SYNC_BRANCH}"
git push bitbucket --tags

echo
echo "Pushed origin/${DEFAULT_BRANCH} to Bitbucket branch '${SYNC_BRANCH}'."
echo "Open a pull request to merge it into ${DEFAULT_BRANCH}:"
echo "  https://bitbucket.org/${BITBUCKET_PATH}/pull-requests/new?source=${SYNC_BRANCH}&dest=${DEFAULT_BRANCH}"
```

## Notes

- Never force-push to Bitbucket's default branch directly - only ever to
  the dedicated sync branch.
- This is intentionally on-demand (a script the user runs), not automatic
  on every push via a CI workflow - keeps timing under the user's control
  and avoids fighting Bitbucket's branch protection on every single commit.
- If the user explicitly says Bitbucket's branch protection allows direct
  pushes from their account (e.g. they added themselves as an exception),
  a simpler fast-forward-only direct push script is fine instead of the
  PR-based one - but don't assume that; ask or let the direct push fail
  once before switching to it.
