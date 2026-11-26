{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./atuin.nix
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

    # nix-your-shell's nix/nix-shell wrappers (keep zsh in `nix shell` and
    # `nix develop`), generated at build time instead of in every shell.
    programs.zsh.initContent = lib.mkOrder 700 ''
      if [[ -o interactive ]]
      then
        source ${
          pkgs.runCommand "nix-your-shell-init.zsh" { } ''
            ${lib.getExe pkgs.nix-your-shell} zsh > $out
          ''
        }
      fi
    '';
  };
}
