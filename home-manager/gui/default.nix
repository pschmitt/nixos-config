{ ... }:
{
  imports = [
    ./autostart.nix
    ./kitty.nix
    ./walker.nix
    ./bookmarks.nix
    ./browser.nix
    ./firefox/pip-volume-scroll.nix
    ./chat.nix
    ./default-apps.nix
    ./dotool.nix
    ./go-hass-agent
    ./gnome-keyring.nix
    ./home-assistant-secrets.nix
    ./lan-mouse.nix
    ./mcp-browser.nix
    ./media.nix
    ./microphone.nix
    ./notes.nix
    ./pipewire-rt.nix
    ./playerctl.nix
    ./profile-picture.nix
    ./yt-dlp-cookies-tx.nix
    ./soundboard.nix
    ./swappy.nix
    ./theme.nix
    ./vimium-c.nix
    ./xdg-portal.nix
    ./yup-startup.nix

    # window managers
    ./gnome.nix
    ./hyprland
    ./niri.nix
    ./noctalia.nix
    # ./vicinae.nix
  ];
}
