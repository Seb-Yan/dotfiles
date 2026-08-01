---
name: github-multi-account
description: Set up permanent, zero-switching access to a GitHub repo that belongs to a different GitHub account than your default one, using a dedicated SSH key and SSH config host alias. Use this whenever the user wants to clone or work with a repo under "another account," "a different GitHub account," or a specific org they don't normally use, mentions avoiding "gh auth switch" or account-switching friction, or hits a SAML SSO authentication error when cloning/pushing (e.g. "must use HTTPS with a personal access token or SSH with an SSH key ... that has been authorized for this organization"). Also use this to diagnose repos already cloned under the wrong account/identity.
---

# GitHub multi-account access via SSH host aliases

## Why this approach

GitHub only lets one identity be "active" at a time for HTTPS-based auth (`gh auth switch`, credential helpers). That means every time you move between repos owned by different accounts, you have to switch again - the friction the user is trying to escape.

SSH doesn't have this limitation. Each GitHub account can have its own dedicated SSH key, and `~/.ssh/config` can map a distinct hostname alias to each key. Once a repo's remote uses that alias, every future `fetch`/`push` on it authenticates as the right account automatically, forever - no switching, ever. This scales to as many accounts as needed: each just gets its own key + alias.

## Sandbox caveat

`~/.ssh` (and often `~/.claude/`) may be outside the directories your tools can read/write directly, even though you can read/write elsewhere. If a command touching `~/.ssh/*` fails with a permissions error, don't work around it - hand the exact command to the user and ask them to run it themselves by prefixing it with `!` in the Claude Code prompt. Everything below is written as commands the user can run this way.

## Steps

**1. Get the target account's username and pick a label.** Usually just the username itself (e.g. `syan_allvue`). This label names the key file and the host alias, so keep it short and stable.

**2. Check for an existing dedicated key:**
```
ls ~/.ssh/id_ed25519_<label>* 2>/dev/null
```
If one already exists, skip to step 4.

**3. Generate a new key dedicated to this account:**
```
ssh-keygen -t ed25519 -C "<label>-github" -f ~/.ssh/id_ed25519_<label> -N ""
```
`-N ""` makes it passphrase-less so it can be used non-interactively. If the user wants a passphrase instead, that's their call - just note it means future git operations may prompt for it.

**4. Add the public key to the target account:**
```
cat ~/.ssh/id_ed25519_<label>.pub
```
The user copies this output into: **GitHub -> Settings -> SSH and GPG keys -> New SSH key**, on the *target* account (not their default one).

**5. Add a host alias to `~/.ssh/config`** (append - never overwrite the existing file, other Host blocks may already be there):
```
cat >> ~/.ssh/config << 'EOF'

Host github.com-<label>
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_<label>
    IdentitiesOnly yes
EOF
```

**6. Verify:**
```
ssh -T git@github.com-<label>
```
Expect a greeting like `Hi <target-username>! You've successfully authenticated...`. If it hangs or fails, double check step 4 was saved and the `IdentityFile` path in step 5 matches step 3 exactly.

**7. Handle SAML SSO if the org requires it.** If cloning/pushing fails with something like:
> `...organization has enabled or enforced SAML SSO. To access this repository, you must use ... SSH with an SSH key ... that has been authorized for this organization.`

the key itself is valid but hasn't been authorized for that specific org yet - this is a separate, per-key, per-org step. Fix: on the target account, go to **Settings -> SSH and GPG keys**, find the key just added, click **"Configure SSO"**, select the org, and authorize (this may redirect through the org's identity provider login). Then retry.

If there's no "Configure SSO" option next to the key at all, the target account likely isn't an accepted member of that org yet (invite still pending) - worth checking org membership before troubleshooting further.

**8. Clone (or repoint an existing repo) using the aliased host** instead of plain `github.com`:
```
git clone git@github.com-<label>:ORG/REPO.git
```
For a repo that's already cloned under the wrong identity:
```
git remote set-url origin git@github.com-<label>:ORG/REPO.git
```

## After setup

Nothing further is needed - this repo's `origin` is now permanently tied to `<label>`'s identity. Repeat steps 1-8 (with a new label) for each additional account the user needs, and each one operates independently with zero ongoing switching.
