{ inputs }:
let
  homes = import ./homes.nix { inherit inputs; };
  # The private lease settings, shared with the bootstrap's setup.conf.
  setup = import ./setup-values.nix {
    inherit (inputs.nixpkgs) lib;
    inherit inputs;
  };
in
builtins.mapAttrs (
  hostname: home:
  import ../../../modules/nixpp/eval.nix {
    inherit inputs;
    inherit (home) pkgs;
    modules = [
      ../../../modules/nixpp/ssh-client.nix
      ../../../modules/nixpp/sshd.nix
      # Host-local system-layer settings (Home Manager ones live in default.nix).
      (
        let
          system = ../../../hosts + "/${hostname}/system.nix";
        in
        if builtins.pathExists system then system else { }
      )
      (
        { config, ... }:
        {
          networking.hostName = hostname;
          sops.defaultSopsFile = inputs.nixos-config-private.outPath + "/hosts/${hostname}/secrets.sops.yaml";
          user = {
            name = home.config.home.username;
            home = home.config.home.homeDirectory;
          };
          system = {
            stateVersion = "1";
            # The Android NDK only runs on x86_64 Linux; the result is still the
            # Android/AArch64 executable.
            nativeNixpp =
              (inputs.termuxpp.lib.nixpp.packagesFor inputs.nixpkgs.legacyPackages.x86_64-linux)
              .nixpp-runtime-termux;
            # Cross-built like nativeNixpp, with the syscall stub at the address
            # of the host's runtime (system.launcherStub); the daemon only
            # installs a launcher that still runs when exec'd under the current
            # one's filter.
            nativeLauncher = (inputs.termuxpp.lib.nixpp.packagesFor inputs.nixpkgs.legacyPackages.x86_64-linux).nixpp-runtime-termux-seed.launcher.withStub config.system.launcherStub;
          };
          environment = {
            systemPackages = with home.pkgs; [
              bashInteractive
              coreutils
              home.config.nix.package
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
              "nixpp/upgrade.json".text = builtins.toJSON (
                {
                  flake = "github:pschmitt/nixos-config/main";
                  host = hostname;
                  cache = home.config.nixpp.upgradeCache;
                  # `nixpp upgrade --rworker` leases a native ARM runner
                  # through the rworker controller with the phone's own key
                  # (the cache credentials are the cache's, above). Phones
                  # reach no OpenStack worker, so no other profile is listed.
                  lease = {
                    inherit (setup.values) controller;
                    controller_host_key = setup.controllerHostKey;
                    owner = "${setup.values.user}@${hostname}";
                    key = "${config.user.home}/.ssh/id_ed25519";
                    profiles = [ "gh-aarch64" ];
                    ssh_inputs = setup.values.sshInputs or [ ];
                  };
                }
                // inputs.nixpkgs.lib.optionalAttrs (config.system.homeManagerBackupExtension != null) {
                  homeManagerBackupExtension = config.system.homeManagerBackupExtension;
                }
              );
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
      )
    ];
  }
) homes
