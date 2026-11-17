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
      {
        networking.hostName = hostname;
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
          SYSTEM_STATE_VERSION=1
        '';
        home-manager.configuration = home;
      }
    ];
  }
) homes
