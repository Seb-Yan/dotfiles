usage() {
  printf '%s\n' \
    'bin: remote-claude' \
    'description: Run Claude Code locally with its Bash tool executing on an SSH host' \
    'usage: remote-claude <ssh-host> [claude args...]' \
    'behavior[4]:' \
    '  Mirrors the current directory to the same path under the remote home' \
    '  Bash tool commands run on the host; file tools stay local over a Mutagen sync' \
    '  Transfers the working tree first, reporting progress and ETA' \
    '  Disables the local sandbox, which cannot constrain another machine' \
    'notes[3]:' \
    '  Run from inside a directory under the home directory' \
    '  Host must be reachable as: ssh <ssh-host>' \
    '  Sync excludes are declared globally in ~/.mutagen.yml'
}

case "${1:-}" in
  ""|help|--help|-h)
    usage
    [ -z "${1:-}" ] && exit 2
    exit 0
    ;;
esac

host="$1"
shift

local_dir="$(pwd -P)"
case "$local_dir/" in
  "$HOME"/*) ;;
  *)
    printf 'error: %s is not under %s\n' "$local_dir" "$HOME" >&2
    printf 'help: remote-claude mirrors paths relative to the home directory\n' >&2
    exit 1
    ;;
esac
rel="${local_dir#"$HOME"}"
rel="${rel#/}"

if ! remote_home="$(ssh -o BatchMode=yes "$host" 'printf %s "$HOME"')"; then
  printf 'error: cannot resolve the home directory on %s\n' "$host" >&2
  printf 'help: check that ssh %s works without a password prompt\n' "$host" >&2
  exit 1
fi

if [ -z "$rel" ]; then
  remote_dir="$remote_home"
else
  remote_dir="$remote_home/$rel"
fi

# Mutagen session names accept alphanumerics, dashes, underscores and dots, and
# must start and end alphanumeric.
sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed -e 's/^[^A-Za-z0-9]*//' -e 's/[^A-Za-z0-9]*$//'
}

humanize_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B KB MB GB TB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

humanize_duration() {
  awk -v s="$1" 'BEGIN {
    s = int(s + 0.5)
    if (s < 60) { printf "%ds", s }
    else if (s < 3600) { printf "%dm%02ds", s / 60, s % 60 }
    else { printf "%dh%02dm", s / 3600, (s % 3600) / 60 }
  }'
}

# Bring the working tree into sync before Claude Code starts, so the wait is
# visible here instead of hiding inside the first Bash tool call.
#
# The session is created fresh and terminated again on every run, deliberately.
# A session that survives between runs carries an ancestor snapshot, and against
# an ancestor Mutagen reads a locally missing file as a deletion and removes it
# on the host too. Without one it reconciles by union, so a file deleted locally
# while nothing was running comes back from the host instead of being destroyed
# there. A cold scan of a 95 MB tree costs about three seconds, which is not
# worth trading that property for.
session_name="rc-$(sanitize "$host")-$(sanitize "${rel:-home}")"
MUTAGEN_DATA_DIRECTORY="${XDG_STATE_HOME:-$HOME/.local/state}/remote-claude/mutagen"
export MUTAGEN_DATA_DIRECTORY
mkdir -p "$MUTAGEN_DATA_DIRECTORY"

sync_create_options=(--sync-mode=two-way-resolved)
# Global excludes live in ~/.mutagen.yml and are inherited without being named
# here. A project may still add its own, which claude-remote-shell also reads.
project_config="$local_dir/.claude/remote-shell/mutagen.yml"
if [ -f "$project_config" ]; then
  sync_create_options+=(-c "$project_config")
  printf '⚙️  Extra sync excludes from %s\n' "${project_config#"$HOME"/}"
fi

# Clear any session left behind by an interrupted run before creating this one.
mutagen sync terminate "$session_name" >/dev/null 2>&1 || true
if ! mutagen sync create --name="$session_name" "${sync_create_options[@]}" \
    "$local_dir" "$host:$remote_dir" >/dev/null; then
  printf 'error: could not create the Mutagen session\n' >&2
  exit 1
fi

# Mutagen reports receivedSize/expectedSize for the file currently in flight,
# not for the whole transfer, so bytes cannot drive an overall percentage.
# beta.totalFileSize is no help either: it only moves when files transition at
# the end. receivedFiles/expectedFiles is the one monotonic overall measure, so
# progress and ETA come from the file count, with bytes shown as detail.
report_progress() {
  local started elapsed json status connected received expected
  local files_received files_expected percent rate eta_text label gap
  local first_files=-1 first_time=0
  started=$(date +%s)

  while :; do
    if ! json=$(mutagen sync list --template '{{json .}}' "$session_name" 2>/dev/null); then
      printf '\nerror: lost track of the Mutagen session\n' >&2
      return 1
    fi

    status=$(printf '%s' "$json" | jq -r '.[0].status // "unknown"')
    [ "$status" = watching ] && break

    connected=$(printf '%s' "$json" | jq -r '[.[0].alpha.connected, .[0].beta.connected] | all')
    if [ "$connected" != true ]; then
      printf '\nerror: endpoint disconnected (status: %s)\n' "$status" >&2
      return 1
    fi

    # stagingProgress is omitted unless an endpoint is receiving files.
    IFS=$'\t' read -r received expected files_received files_expected <<EOF
$(printf '%s' "$json" | jq -r '
  [.[0].alpha.stagingProgress, .[0].beta.stagingProgress]
  | map(select(. != null)) | (.[0] // {})
  | [(.receivedSize // 0), (.expectedSize // 0),
     (.receivedFiles // 0), (.expectedFiles // 0)] | @tsv')
EOF

    elapsed=$(( $(date +%s) - started ))
    if [ "${files_expected:-0}" -gt 0 ]; then
      if [ "$first_files" -lt 0 ]; then
        first_files=$files_received
        first_time=$(date +%s)
      fi
      percent=$(( files_received * 100 / files_expected ))
      eta_text="--"
      rate=$(( $(date +%s) - first_time ))
      if [ "$rate" -ge 2 ] && [ "$files_received" -gt "$first_files" ]; then
        eta_text=$(humanize_duration \
          "$(( (files_expected - files_received) * rate / (files_received - first_files) ))")
      fi
      gap=$(printf '%s' "$json" | jq -r '
        [(.[0].alpha.totalFileSize // 0), (.[0].beta.totalFileSize // 0)]
        | (max - min)')
      label=$(printf '%s %d%%  %s/%s files  in flight %s/%s  ~%s to move  ETA %s' \
        "$status" "$percent" "$files_received" "$files_expected" \
        "$(humanize_bytes "$received")" "$(humanize_bytes "$expected")" \
        "$(humanize_bytes "$gap")" "$eta_text")
    else
      label=$(printf '%s  %s elapsed' "$status" "$(humanize_duration "$elapsed")")
    fi

    if [ -t 1 ]; then
      printf '\r\033[K🔄 %s' "$label"
    else
      printf '🔄 %s\n' "$label"
    fi
    sleep 2
  done

  [ -t 1 ] && printf '\r\033[K'
  printf '✅ In sync: %s files, %s\n' \
    "$(printf '%s' "$json" | jq -r '.[0].alpha.files // 0')" \
    "$(humanize_bytes "$(printf '%s' "$json" | jq -r '.[0].alpha.totalFileSize // 0')")"
}

if ! report_progress; then
  printf 'help: inspect it with MUTAGEN_DATA_DIRECTORY=%s mutagen sync list %s\n' \
    "$MUTAGEN_DATA_DIRECTORY" "$session_name" >&2
  exit 1
fi

# Terminate before handing off: claude-remote-shell creates its own session for
# the same pair, and two active sessions would fight over the same files.
mutagen sync terminate "$session_name" >/dev/null 2>&1 || true
mutagen daemon stop >/dev/null 2>&1 || true

# Claude Code's sandbox is a local macOS mechanism. With the Bash tool executing
# on another machine it protects nothing there, and it exports HTTP_PROXY
# pointing at a localhost port that only exists on this Mac, which breaks every
# remote command that touches the network.
exec claude-remote-shell "$host:$remote_dir" \
  --settings '{"sandbox":{"enabled":false,"failIfUnavailable":false,"allowUnsandboxedCommands":true}}' \
  "$@"
