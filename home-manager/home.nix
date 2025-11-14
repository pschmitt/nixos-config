{
  inputs,
  lib,
  config,
  osConfig,
  pkgs,
  ...
}:
let
  # DIRTYFIX for ssh keys transferred via nixos-anywhere's --extra-files option
  # All files are owned by root, which makes sops-nix unhappy
  fixSshOwnership = pkgs.writeShellScript "hm-fix-ssh-ownership" ''
    SUDO_BIN="/run/wrappers/bin/sudo"
    DIR='${osConfig.custom.homeDirectory}/.ssh'

    if [[ ! -d "$DIR" ]]
    then
      exit 0
    fi

    echo "Ensuring ownership on $DIR"
    if ! "$SUDO_BIN" -n chown -R "${osConfig.custom.username}:${osConfig.custom.username}" "$DIR"
    then
      echo "Could not change ownership on $DIR (needs passwordless sudo)" >&2
      exit 1
    fi
  '';
in
{
  imports = lib.concatLists [
    [
      inputs.catppuccin.homeModules.catppuccin
      inputs.nix-index-database.homeModules.nix-index
      inputs.sops-nix.homeManagerModules.sops

      ./banking.nix
      ./bitwarden.nix
      ./crypto.nix
      ./devel.nix
      ./flatpak.nix
      ./hyprland.nix
      ./gnome-keyring.nix
      ./mail.nix
      ./mani.nix
      ./misc.nix
      ./networking.nix
      ./nrf.nix
      ./nvim.nix
      ./ssh.nix
      ./work.nix
      ./yadm.nix
      ./zsh.nix
      # ./zellij.nix
    ]
    (lib.optional osConfig.hardware.bluetooth.enable ./bluetooth.nix)
    (lib.optional osConfig.services.xserver.enable ./gui)
  ];

  sops = {
    inherit (osConfig.sops) defaultSopsFile;
    age.sshKeyPaths = [ "${osConfig.custom.homeDirectory}/.ssh/id_ed25519" ];
    age.generateKey = false;
  };

  systemd.user.services.sops-nix.Service.ExecStartPre =
    lib.mkBefore [ "${fixSshOwnership}" ];

  programs.home-manager.enable = true;

  programs.nix-index-database.comma.enable = true;

  systemd.user.startServices = "sd-switch";

  home = {
    # The home.stateVersion option does not have a default and must be set
    inherit (osConfig.system) stateVersion;

    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.local/share/polaris/bin"
      "${config.home.homeDirectory}/bin"
    ];

    packages = with pkgs; [
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

    ];

    # AccountService profile picture
    file = {
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
