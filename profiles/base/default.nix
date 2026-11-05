{
  config,
  pkgs,
  ...
}:
{
  # Preserve the shared role baseline: feature implementation lives separately.
  # Keep these positions stable; import order affects merged lists.
  imports = [
    ../features/development/android-usb.nix
    ../features/desktop/appimage.nix
    ./atd.nix
    ./boot.nix
    ./btrfs.nix
    ./bootloader.nix
    ../features/containers
    ./dict.nix
    ./dotfiles.nix
    ./locales.nix
    ./nix.nix
    ./ntp.nix
    ./packages.nix
    ./sops.nix
    ./ssh.nix
    ./users.nix
  ];

  hardware.enableAllFirmware = true;

  environment.sessionVariables.HOSTNAME = config.networking.hostName;

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # mlocate
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    interval = "daily";
  };
}
