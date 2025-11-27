{ ... }:
{
  imports = [
    ./autostart.nix
    ./browser.nix
    ./chat.nix
    ./default-apps.nix
    ./dotool.nix
    ./gnome-keyring.nix
    ./media.nix
    ./podsync-cookies-tx.nix
    ./soundboard.nix
    ./theme.nix

    # window managers
    ./gnome.nix
    ./hyprland
    ./niri.nix
    # ./dank.nix
    # ./vicinae.nix
  ];
}
