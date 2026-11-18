{ inputs }:
let
  homes = import ../default.nix { inherit inputs; };
in
builtins.mapAttrs (
  hostname: home:
  import ./. {
    inherit inputs;
    inherit (home) pkgs;
    modules = [
      ./sshd.nix
      {
        networking.hostName = hostname;
        sops.defaultSopsFile = inputs.nixos-config-private.outPath + "/hosts/${hostname}/secrets.sops.yaml";
        user = {
          name = home.config.home.username;
          home = home.config.home.homeDirectory;
        };
        system.stateVersion = "1";
        environment.systemPackages = with home.pkgs; [
          bashInteractive
          coreutils
          nix
          openssh
          cacert
        ];
        environment.etc."termuxpp-release".text = ''
          ID=termuxpp
          RUNTIME=droid-nix
          XDG_RUNTIME_DIR_LAYOUT=run-user
          SYSTEM_STATE_VERSION=1
        '';
        home-manager.configuration = home;
      }
    ];
  }
) homes
