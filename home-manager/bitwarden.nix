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
      primaryAccount = "default";
      agent = {
        lockTimeout = 86400;
        syncInterval = 3600;
      };
      pinentry = {
        command = "pinentry";
      };
      tui = {
        keys = {
          # Matches the <M-Q> "rage quit" mapping in neovim: exit the TUI
          # immediately from any mode, even mid-dialog.
          forceQuit = [ "alt-Q" ];
        };
      };
      # Shortcut names for `rbw get`, replacing the hand-maintained
      # name-remapping table that used to live in the `rbw::get` zsh
      # function (~/.config/zsh/plugins/local/rbw.zsh). TOTP-appending and
      # tmux-buffer side effects aren't expressible here (they're shell
      # behavior, not vault data) and stay in that zsh function, keyed by
      # the same alias names. All target items live in the `default`
      # account (verified via `rbw -a default list`) despite several of
      # these names sounding WIIT-specific -- they're the user's own
      # personal-vault items for a former/current work context, not
      # entries in the separate `wiit` Vaultwarden account, so no
      # `account` override is needed here.
      aliases = [
        {
          alias = [
            "gpg"
            "gnupg"
          ];
          item = "Private GPG Key";
        }
        {
          alias = [
            "gpg-gec"
            "gpg-wiit"
            "gpg-work"
          ];
          item = "WIIT GPG Key";
        }
        {
          alias = [
            "gec"
            "voffice"
          ];
          item = "desktop.gec.io";
        }
        {
          alias = [
            "gec-mgmt"
            "mgmt"
            "mgmt-legacy"
            "gec-vpn"
            "gec-vpn-legacy"
          ];
          item = "gec.io VPN (Sophos)";
        }
        {
          alias = [
            "google"
            "gmail"
          ];
          item = "🔖 google.com (${config.mainUser.email})";
        }
        {
          alias = [
            "ovpn"
            "gec-ovpn"
          ];
          item = "GEC OpenVPN v2";
        }
        {
          alias = [
            "vpn"
            "wiit-vpn"
          ];
          item = "vpn.wiit.one";
        }
        {
          alias = [
            "rancher.wiit-edge.services"
            "rancher-legacy.wiit-edge.services"
            "rancher-staging.wiit-edge.services"
          ];
          item = "Rancher (WIIT)";
        }
      ];
      accounts = {
        default.email = config.mainUser.email;
        wiit = {
          email.file = config.sops.secrets."rbw/work/email".path;
          baseUrl.file = config.sops.secrets."rbw/work/base_url".path;
          unlock = {
            policy = "always";
            credentials.account = "default";
          };
        };
        bw = {
          email.file = config.sops.secrets."rbw/private/email".path;
          baseUrl.file = config.sops.secrets."rbw/private/base_url".path;
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
          excludeFrom = [
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
        # Not sops-secret'd like `bw`/`wiit`: email/baseUrl for a
        # throwaway test account aren't sensitive.
        ai = {
          email = "ai@brkn.lol";
          baseUrl = "https://bw.brkn.lol";
          unlock = {
            policy = "always";
            credentials = {
              account = "default";
              item = "Vaultwarden (ai@brkn.lol)";
            };
          };
          excludeFrom = [
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
