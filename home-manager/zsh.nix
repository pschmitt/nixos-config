{ inputs, pkgs, ... }:
{
  home.file = {
    ".config/zsh/custom/os/nixos/system.zsh" = {
      text = ''
        if [[ -o interactive && -o login ]]
        then
          # command-not-found integration
          source ${inputs.nix-index-database.packages.${pkgs.system}.nix-index-with-db}/etc/profile.d/command-not-found.sh

          # DEPRECATED: Use wezterm.sh instead
          # source ${pkgs.vte}/etc/profile.d/vte.sh

          # FIXME the osc7 shell func produces output which p10k complains about
          # on startup (hence the WEZTERM_SHELL_SKIP_CWD)
          WEZTERM_SHELL_SKIP_CWD=1 source ${pkgs.wezterm}/etc/profile.d/wezterm.sh
        fi
      '';
    };
  };
}
