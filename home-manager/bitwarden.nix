{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.rbw.homeManagerModules.default ];

  sops.secrets = {
    "rbw/private/email" = { };
    "rbw/private/base_url" = { };
    "rbw/work/email" = { };
    "rbw/work/base_url" = { };
  };

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
        default.email = config.mainUser.email;
        wiit = {
          email._secret = config.sops.secrets."rbw/work/email".path;
          base_url._secret = config.sops.secrets."rbw/work/base_url".path;
          unlock = {
            policy = "always";
            credentials.account = "default";
          };
        };
        bw = {
          email._secret = config.sops.secrets."rbw/private/email".path;
          base_url._secret = config.sops.secrets."rbw/private/base_url".path;
          unlock = {
            policy = "always";
            # `item` is pinned explicitly: `default`'s vault has two
            # bw.brkn.lol Login items (this one, and the `ai` account's
            # below), so a plain URI match is ambiguous.
            credentials = {
              account = "default";
              item = "Vaultwarden";
            };
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
        # Disposable test account (bw.brkn.lol Vaultwarden) used for rbw
        # development/smoke-testing -- never anything real. Its master
        # password lives as a Login item in `default`'s own vault; `item`
        # is set explicitly since `bw` above also targets bw.brkn.lol and
        # would otherwise collide on a plain URI match against `default`.
        # Not sops-secret'd like `bw`/`wiit`: email/base_url for a
        # throwaway test account aren't sensitive.
        ai = {
          email = "ai@brkn.lol";
          base_url = "https://bw.brkn.lol";
          unlock = {
            policy = "always";
            credentials = {
              account = "default";
              item = "Vaultwarden (ai@brkn.lol)";
            };
          };
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
