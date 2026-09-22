{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Companion to home-manager/sops.nix's own fixSshOwnership: that one runs
  # before the user-level sops-nix.service, but nixos-anywhere's --extra-files
  # leaves ~/.ssh root-owned even earlier than that, which breaks the
  # system-level home-manager-<user>.service itself (runs as User=pschmitt)
  # while it's trying to link home.file entries (e.g. ssh.nix) into ~/.ssh.
  fixSshOwnership = pkgs.writeShellScript "hm-system-fix-ssh-ownership" ''
    DIR='${config.mainUser.homeDirectory}/.ssh'
    if [[ -d "$DIR" ]]; then
      chown -R '${config.mainUser.username}:${config.mainUser.username}' "$DIR"
    fi
  '';
in
{
  imports = [
    # Import home-manager's NixOS module
    inputs.home-manager.nixosModules.home-manager
  ];

  systemd.services."home-manager-${config.mainUser.username}".serviceConfig.ExecStartPre =
    lib.mkBefore
      [ "+-${fixSshOwnership}" ];

  home-manager = {
    # Import-gating facts go through specialArgs (not config) so home.nix can
    # branch its `imports` without a config-in-imports infinite recursion.
    extraSpecialArgs = {
      inherit inputs hostname;
      guiEnable = config.services.xserver.enable;
      bluetoothEnable = config.hardware.bluetooth.enable;
    };

    backupFileExtension = "hm-backup";
    useGlobalPkgs = true;
    useUserPackages = true;

    users.${config.mainUser.username} = {
      imports = [
        ./home.nix
      ];

      # Bridge: feed system facts from the NixOS config into the (osConfig-free)
      # home config. Standalone hosts set these explicitly instead.
      inherit (config) mainUser domains;
      dotfiles = {
        promptColor = config.dotfiles.promptColor;
        inherit (config.dotfiles) desktop;
      };
      host = {
        sopsFile = config.sops.hostSopsFile;
        sopsDefaultFile = config.sops.defaultSopsFile;
        highDpi = config.hardware.highDpi;
        nvidiaPrimeOffload = config.hardware.nvidia.prime.offload.enable;
        iioSensor = config.hardware.sensor.iio.enable;
        touchscreen = config.hardware.touchscreen.enable;
        provisionSshKeys = true;
        uid =
          let
            u = config.users.users.${config.mainUser.username}.uid;
          in
          if u == null then 1000 else u;
        stateVersion = config.system.stateVersion;
      };
    };
  };
}
