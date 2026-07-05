{ pkgs, inputs, ... }:
{
  imports = [ inputs.rbw.homeManagerModules.default ];

  home.packages = with pkgs; [
    # NOTE For the biometrics to work, the bitwarden-deskop pkg must be installed
    # as a system package. See:
    # https://github.com/NixOS/nixpkgs/pull/339384
    # bitwarden-desktop
    master.bitwarden-cli
  ];

  # rbw itself is installed by programs.rbw.declarative below (same
  # derivation as the `rbw` overlay in overlays/rbw.nix).
  programs.rbw.declarative = {
    enable = true;
    settings = {
      primary_account = "default";
      lock_timeout = 86400;
      sync_interval = 3600;
      pinentry = "pinentry";
      tui_keybindings = {
        # Matches the <M-Q> "rage quit" mapping in neovim: exit the TUI
        # immediately from any mode, even mid-dialog.
        force_quit = [ "alt-Q" ];
      };
      accounts = {
        default.email = "philipp@schmitt.co";
        wiit = {
          email = "philipp.schmitt@wiit.cloud";
          base_url = "https://vault.wiit.one";
          unlock = {
            policy = "always";
            credentials.account = "default";
          };
        };
        bw = {
          email = "philipp@schmitt.co";
          base_url = "https://bw.brkn.lol";
          unlock = {
            policy = "always";
            credentials.account = "default";
          };
          # Mirrors the `default` account; excluded from every list/search/
          # get-style merge so it doesn't break those by default. Not
          # excluded from `tui`, so it still shows up there. Still reachable
          # via `rbw --account bw ...`.
          exclude_from = [
            "list"
            "search"
            "get"
            "show"
            "code"
            "sync"
            "unlock"
          ];
        };
      };
    };
  };
}
