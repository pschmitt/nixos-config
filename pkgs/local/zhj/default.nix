# `zhj`: run a zsh function, alias or command with the Nix-managed zsh config
# (Home Manager's programs.zsh.dotDir, ~/.config/zsh by default) loaded.
{
  lib,
  writeShellApplication,
  zsh,
  # Absolute ZDOTDIR; null means $XDG_CONFIG_HOME/zsh at runtime.
  dotDir ? null,
}:
writeShellApplication {
  name = "zhj";
  runtimeInputs = [ zsh ];
  text = ''
    export ZDOTDIR=${
      if dotDir == null then ''"''${XDG_CONFIG_HOME:-$HOME/.config}/zsh"'' else lib.escapeShellArg dotDir
    }
    exec ${zsh}/bin/zsh -f -c 'source ${./zhj.zsh}' -- "$@"
  '';
  meta = {
    description = "Run zsh functions with the Nix-managed zsh config loaded";
    platforms = lib.platforms.unix;
    mainProgram = "zhj";
  };
}
