#!/usr/bin/env bash
# PreToolUse hook for the Bash tool: hard-blocks a short list of catastrophic
# command patterns regardless of how permissions/sandbox are otherwise configured.
# This is defense-in-depth on top of the sandbox.* filesystem/network/credential
# config in settings.json, not a replacement for it - pattern matching on a
# command string can always be evaded by rephrasing, the sandbox enforcement
# cannot.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

if [ -z "$cmd" ]; then
  exit 0
fi

# sudo / privilege escalation
if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*sudo[[:space:]]'; then
  deny "sudo is blocked by policy - if a task genuinely needs elevated privileges, stop and ask the human"
fi

# recursive delete targeting home or filesystem root
if printf '%s' "$cmd" | grep -qE '\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)[[:space:]]+(~([[:space:]]|$|/[[:space:]]|/$)|\$HOME\b|/([[:space:]]|$)|/\*)'; then
  deny "recursive delete targeting home or filesystem root is blocked"
fi

# piping remote content straight into a shell
if printf '%s' "$cmd" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)([[:space:]]|$)'; then
  deny "piping curl/wget output into a shell is blocked - download and inspect first"
fi

# force push
if printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+push\b.*(--force\b|--force-with-lease\b|[[:space:]]-f\b)'; then
  deny "force push is blocked - open a PR instead of rewriting remote history"
fi

# direct push to a protected branch name
if printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+push\b.*\b(origin[[:space:]]+)?(main|master|production|release)\b'; then
  deny "direct push to a protected branch is blocked - push a feature branch and open a PR"
fi

exit 0
