{ writeShellApplication, claude-remote-shell, mutagen, jq, gawk }:

writeShellApplication {
  name = "remote-claude";
  # Deliberately no openssh. claude-remote-shell opens an SSH ControlMaster in
  # this process and the Bash tool wrapper later reuses that socket from a login
  # shell, where PATH resolves to /usr/bin/ssh. A second OpenSSH on PATH makes
  # the master and its clients different versions, and the mux protocol is not
  # compatible across versions: the master closes the control connection and
  # every command fails with "mux_client_request_session: write packet: Broken
  # pipe".
  runtimeInputs = [ claude-remote-shell mutagen jq gawk ];
  text = builtins.readFile ./remote-claude.sh;

  meta.description = "Run Claude Code locally with its Bash tool executing on an SSH host";
}
