{ inputs }:
let
  homes = import ./homes.nix { inherit inputs; };
in
builtins.mapAttrs (
  hostname: home:
  import ../../../modules/nixpp/eval.nix {
    inherit inputs;
    inherit (home) pkgs;
    modules = [
      ../../../modules/nixpp/ssh-client.nix
      ../../../modules/nixpp/sshd.nix
      {
        networking.hostName = hostname;
        sops.defaultSopsFile = inputs.nixos-config-private.outPath + "/hosts/${hostname}/secrets.sops.yaml";
        user = {
          name = home.config.home.username;
          home = home.config.home.homeDirectory;
        };
        system.stateVersion = "1";
        environment = {
          systemPackages = with home.pkgs; [
            bashInteractive
            coreutils
            nix
            openssh
            cacert
          ];
          etc = {
            # The guest zsh reads /etc/zshenv before any user file; point it at
            # the Home Manager dotDir so no ~/.zshenv is needed.
            "zshenv".text = ''
              # Sessions started before the move still export ~/.config/zsh-nix.
              [[ "''${ZDOTDIR:-}" == "$HOME/.config/zsh-nix" ]] && unset ZDOTDIR
              export ZDOTDIR="''${ZDOTDIR:-${home.config.programs.zsh.dotDir}}"
            '';
            "nixpp/upgrade.json".text = builtins.toJSON {
              flake = "github:pschmitt/nixos-config/main";
              host = hostname;
              cache = home.config.fullNix.upgradeCache;
            };
            "termuxpp-release".text = ''
              ID=termuxpp
              RUNTIME=droid-nix
              XDG_RUNTIME_DIR_LAYOUT=run-user
              SYSTEM_STATE_VERSION=1
            '';
          };
        };
        home-manager.configuration = home;
      }
    ];
  }
) homes
