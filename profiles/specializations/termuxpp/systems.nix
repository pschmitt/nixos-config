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
            "ssh/termuxpp-client.conf".text = "ControlPath none\n";
            "nixpp/upgrade.json".text = builtins.toJSON {
              flake = "github:pschmitt/nixos-config/main";
              host = hostname;
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
