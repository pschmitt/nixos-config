{ ... }:
{
  imports = [
    ./autostart.nix
    ./kitty.nix
    ./walker.nix
    ./bookmarks.nix
    ./browser.nix
    ./chat.nix
    ./default-apps.nix
    ./dotool.nix
    ./go-hass-agent
    ./gnome-keyring.nix
    ./home-assistant-secrets.nix
    # ./clipcascade.nix
    ./media.nix
    ./notes.nix
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
