{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./completions
    ./config/base.nix
    ./config/hashicorp-completions.nix
    ./config/hm.nix
    ./config/portable.nix
    ./plugins
    ./termux-shell.nix
    ./tools
    ./tools/termux
    ../../../modules/home-manager/termux-zsh-runtime.nix
    ../../termux-options.nix
  ];

  home.packages = [ pkgs.python3 ];

  home.sessionVariables = {
    UDOCKER_DIR = "${config.xdg.dataHome}/udocker";
    UDOCKER_BIN = "${pkgs.udocker-engines}/bin";
    UDOCKER_LIB = "${pkgs.udocker-engines}/lib";
    UDOCKER_DOC = "${pkgs.udocker-engines}/share/doc";
    UDOCKER_USE_PROOT_EXECUTABLE = "${pkgs.proot}/bin/proot";
    UDOCKER_DEFAULT_EXECUTION_MODE = "P1";
  };
}
