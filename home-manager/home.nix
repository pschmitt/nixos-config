{
  inputs,
  lib,
  config,
  osConfig,
  pkgs,
  ...
}:
{
  imports = lib.concatLists [
    [
      inputs.catppuccin.homeModules.catppuccin
      inputs.nix-index-database.homeModules.nix-index
      inputs.sops-nix.homeManagerModules.sops

      ./banking.nix
      ./bitwarden.nix
      ./cli
      ./crypto.nix
      ./devel
      ./env.nix
      ./flatpak.nix
      ./mail.nix
      ./mani.nix
      ./networking.nix
      ./nrf.nix
      ./nvim.nix
      ./gpg.nix
      ./sops.nix
      ./ssh.nix
      ./work
      ./yadm.nix
      ./zsh
      # ./zellij.nix
    ]
    (lib.optional osConfig.hardware.bluetooth.enable ./bluetooth.nix)
    (lib.optional osConfig.services.xserver.enable ./gui)
  ];

  programs.home-manager.enable = true;

  programs.nix-index-database.comma.enable = true;

  systemd.user.startServices = "sd-switch";

  home = {
    # The home.stateVersion option does not have a default and must be set
    inherit (osConfig.system) stateVersion;

    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.local/share/polaris/bin" # $ZPFX (zinit)
      "${config.home.homeDirectory}/bin"
    ];

    # AccountService profile picture
    file = {
      ".face" = {
        enable = true;
        source = config.lib.file.mkOutOfStoreSymlink "/var/lib/AccountsService/icons/${config.home.username}";
      };
    };
  };

  gtk = {
    enable = true;
    # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
    gtk3 = {
      bookmarks = [
        "file://${config.home.homeDirectory}/devel/private 💻 dev-p"
        "file://${config.home.homeDirectory}/devel/work 💻 dev-w"
        "file://${config.home.homeDirectory}/Backups 💾 backups"
        "file://${config.home.homeDirectory}/Documents 📄 documents"
        "file://${config.home.homeDirectory}/Downloads 📥 downloads"
        "file://${config.home.homeDirectory}/Music 🎵 music"
        # "file://${config.home.homeDirectory}/Public 📂 public"
        "file://${config.home.homeDirectory}/Pictures 📷 pictures"
        # "file://${config.home.homeDirectory}/Templates 📄 templates"
        "file://${config.home.homeDirectory}/Videos 🎥 videos"
        "file:///tmp 🗑 tmp"
        "file:///mnt/data 🖧 data"
        "file:///mnt/turris 🖧 turris"
        "file:///mnt/hass 🖧 hass"
      ];
    };
  };
}
