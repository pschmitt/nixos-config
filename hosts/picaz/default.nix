{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./config-txt.nix
    ./camera.nix
    ./ssh.nix

    # Selective subset of profiles/global — skip boot.nix (sets linux_rpi4),
    # containers.nix (docker), and packages.nix (too heavy for 512 MB / ARMv6).
    # locales.nix is skipped because it references pkgs.custom-keymaps (overlay
    # not available on armv6l); locale/tz are inlined below instead.
    ../../profiles/global/ntp.nix
    ../../profiles/global/sops.nix
    ../../profiles/global/ssh-server.nix
    ../../profiles/global/users/root.nix
  ];

  hardware.cattle = true;
  hardware.kvmGuest = false;

  console.keyMap = "de";
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Berlin";

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);

    firewall.enable = false;

    # wpa_supplicant — lighter than NetworkManager on a Zero W
    wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi/psk".path;
      networks."brkn-lan".psk = "@WIFI_HOME_PSK@";
    };
  };

  sops.secrets."wifi/psk" = config.custom.mkSecret { };

  # Minimal user: locked password, SSH-key auth only.
  # Keys come from mainUser.authorizedKeys (fetched from GitHub at build time).
  users = {
    mutableUsers = false;
    users."${config.mainUser.username}" = {
      isNormalUser = true;
      hashedPassword = "!";
      extraGroups = [
        "wheel"
        "video"
      ];
      openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;
      shell = pkgs.bash;
    };
    groups."${config.mainUser.username}" = { };
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    experimental-features = "nix-command flakes";
    trusted-users = [
      "root"
      "@wheel"
    ];
  };

  environment.systemPackages = with pkgs; [
    curl
    htop
    v4l-utils
  ];

  system.stateVersion = "25.11";
}
