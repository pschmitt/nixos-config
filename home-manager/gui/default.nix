{ ... }:
{
  imports = [
    ./autostart.nix
    ./bookmarks.nix
    ./browser.nix
    ./chat.nix
    ./default-apps.nix
    ./dotool.nix
    ./gnome-keyring.nix
    ./clipcascade.nix
    ./media.nix
    ./profile-picture.nix
    ./yt-dlp-cookies-tx.nix
    ./soundboard.nix
    ./theme.nix
    ./xdg-portal.nix

    # window managers
    ./gnome.nix
    ./hyprland
    ./niri.nix
    # ./dank.nix
    # ./vicinae.nix
  ];
}
