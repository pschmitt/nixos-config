{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.tesmart-cli ];

  programs.zsh.initContent = lib.mkOrder 620 ''
    tesmart() {
      command tesmart \
        -c ${lib.escapeShellArg "${config.xdg.configHome}/zsh/custom/tesmart-config.sh"} \
        -H "tesmart-kvm-switch.lan" \
        "$@"
    }
  '';
}
