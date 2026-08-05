{ lib, stdenvNoCC, fetchFromGitHub }:

# Installed unwrapped on purpose: the script dispatches on `basename "$0"` and
# re-execs itself through symlinks named `bash`, `session-start` and
# `session-end`. A makeWrapper indirection renames it to
# `.claude-remote-shell-wrapped`, which matches no case branch and exits 0
# silently. Runtime dependencies (mutagen, jq, awk, ssh, claude) come from PATH.
stdenvNoCC.mkDerivation {
  pname = "claude-remote-shell";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "torarnv";
    repo = "claude-remote-shell";
    rev = "dcad0de0b9d5b94aac4c73af9b3aa6362190963d"; # v0.1.4
    hash = "sha256-fRVRkNq7jFtK+Dp4yUlY5/4L0rRMl945DC0NZV9ZgOM=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 claude-remote-shell "$out/bin/claude-remote-shell"
    ln -s claude-remote-shell "$out/bin/claude-remote-shell-yolo"
    runHook postInstall
  '';

  meta = {
    description = "Redirect Claude Code's Bash tool commands to a remote machine over SSH";
    homepage = "https://github.com/torarnv/claude-remote-shell";
    license = lib.licenses.mit;
    mainProgram = "claude-remote-shell";
    platforms = lib.platforms.darwin;
  };
}
