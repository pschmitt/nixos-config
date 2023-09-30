{ config, pkgs, ... }:
{
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  users.users.pschmitt = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      vim
    ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys =
      let
        authorizedKeys = builtins.fetchurl {
          url = "https://github.com/pschmitt.keys";
          sha256 = "0s2ix9lmhv5vc6av3jymhkkm41dbq7acbjqryb5l1lsmax159fh8";
        };
      in
      pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  };

  # services.cloud-init.enable = true;
  services.openssh.enable = true;

  system.stateVersion = "23.05";
}
