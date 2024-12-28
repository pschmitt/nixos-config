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
      inputs.sops-nix.homeManagerModules.sops
      inputs.nur.modules.homeManager.default
      inputs.nix-index-database.hmModules.nix-index
      inputs.catppuccin.homeManagerModules.catppuccin
      ./bitwarden.nix
      ./crypto.nix
      ./devel.nix
      ./mail.nix
      ./mani.nix
      ./misc.nix
      ./networking.nix
      ./nvim.nix
      ./work.nix
      ./yadm.nix
      ./zsh.nix
      # ./zellij.nix
    ]
    (lib.optional (osConfig.hardware.bluetooth.enable) ./bluetooth.nix)
    (lib.optional (osConfig.services.xserver.enable) ./gui)
  ];

  # FIXME Do we need that for anything?
  # nixpkgs.overlays = [
  #   inputs.nur.overlay
  # ];

  # The home.stateVersion option does not have a default and must be set
  home.stateVersion = osConfig.system.stateVersion;

  sops = {
    defaultSopsFile = osConfig.sops.defaultSopsFile;
    age.sshKeyPaths = [ "/home/pschmitt/.ssh/id_ed25519" ];
    age.generateKey = false;
  };

  programs.home-manager.enable = true;

  programs.nix-index-database.comma.enable = true;

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.local/share/polaris/bin"
    "${config.home.homeDirectory}/bin"
  ];

  home.packages = with pkgs; [
    home-manager
    # nwg-displays
    # thunderbird

    # cli
    age
    atuin
    bat
    direnv
    emoji-fzf
    eza
    fd
    fzf
    gyb
    jc
    jsonrepair
    # rich-cli fails to build as of 2024-05-10 (rich-rst's test fail)
    # rich-cli
    sops
    ssh-to-age
    yadm

    # gui
    gimp
    nextcloud-client

    # chat
    element-desktop
    signal-desktop

    # iot
    mosquitto
    net-snmp

    # virtualization
    distrobox
    # quickemu # fails to build as of 28.12.2024
    # quickgui # fails to build as of 09.09.2024

    # devel
    android-tools
    # ansible
    codespell
    flarectl
    openssl
    shellcheck

    # nix
    alejandra
    cachix
    niv
    nix-init
    nixfmt-rfc-style
    nixos-anywhere
    nixos-generators
    nixpkgs-fmt
  ];

  # AccountService profile picture
  home.file = {
    ".face" = {
      enable = true;
      source = builtins.fetchurl {
        # NOTE setting the extension to .png is required for hyprlock to detect
        # the filetype correctly
        # https://github.com/hyprwm/hyprlock/issues/317
        name = "face.png";
        url = "https://www.gravatar.com/avatar/8635e7a28259cb6da1c6a3c96c75b425.png?size=96";
        sha256 = "1kg0x188q1g2mph13cs3sm4ybj3wsliq2yjz5qcw4qs8ka77l78p";
      };
    };
  };

  gtk = {
    enable = true;
    # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
    gtk3 = {
      bookmarks = [
        "file:///tmp 🗑 tmp"
        "file:///mnt/data 🖧 data"
        "file:///mnt/turris 🖧 turris"
        "file:///mnt/hass 🖧 hass"
        "file://${config.home.homeDirectory}/devel/private 💻 dev-p"
        "file://${config.home.homeDirectory}/devel/work 💻 dev-w"
        "file://${config.home.homeDirectory}/Documents 📄 documents"
        "file://${config.home.homeDirectory}/Downloads 📥 downloads"
        "file://${config.home.homeDirectory}/Music 🎵 music"
        # "file://${config.home.homeDirectory}/Public 📂 public"
        "file://${config.home.homeDirectory}/Pictures 📷 pictures"
        # "file://${config.home.homeDirectory}/Templates 📄 templates"
        "file://${config.home.homeDirectory}/Videos 🎥 videos"
      ];
    };
  };
}
