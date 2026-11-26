{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./atuin.nix
    ./config/source-me.nix
    ./direnv.nix
    ./fzf.nix
    ./vivid.nix
    ./zoxide.nix
  ];

  config = {
    programs.zsh = {
      # Enabled by ./config when the Nix-managed shell is opted into.
      enable = lib.mkDefault false;
      dotDir = lib.mkDefault "${config.xdg.configHome}/zsh/hm";
    };

    home = {
      shell.enableZshIntegration = true;

      activation.clearZshCompDump = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run rm -f ${config.xdg.cacheHome}/zcompdump
      '';

      packages = [
        pkgs.gitstatus # used by p10k
        pkgs.nix-your-shell
      ];
    };

    xdg.configFile = {
      "zsh/custom/os/home-manager/system.zsh".text = ''
        [[ -o interactive ]] || return
      '';

      "zsh/custom/os/nixos/system.zsh".text = ''
        source "${config.xdg.configHome}/zsh/custom/os/home-manager/system.zsh"
      '';
    };
  };
}
