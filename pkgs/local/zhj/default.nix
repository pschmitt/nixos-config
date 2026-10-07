# `zhj`: run a zsh function, alias or command with the Nix-managed zsh config
# (~/.config/zsh-nix, Home Manager's programs.zsh.dotDir) loaded. The yadm
# ~/bin/zhj (zinit hosts) hands off to this one when it is installed.
{
  lib,
  writeShellApplication,
  zsh,
}:
writeShellApplication {
  name = "zhj";
  runtimeInputs = [ zsh ];
  text = ''
    export ZDOTDIR="''${XDG_CONFIG_HOME:-$HOME/.config}/zsh-nix"
    exec ${zsh}/bin/zsh -f -c 'source ${./zhj.zsh}' -- "$@"
  '';
  meta = {
    description = "Run zsh functions with the Nix-managed zsh config loaded";
    platforms = lib.platforms.unix;
    mainProgram = "zhj";
  };
}
