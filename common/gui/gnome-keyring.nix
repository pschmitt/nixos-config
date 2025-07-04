{ pkgs, ... }:
{

  # Below is required to unlock the keyring with the LUKS passphrase
  # https://discourse.nixos.org/t/automatically-unlocking-the-gnome-keyring-using-luks-key-with-greetd-and-hyprland/54260/3
  boot.initrd.systemd.enable = true;

  services.dbus = {
    enable = true;
    packages = [ pkgs.gcr ];
  };

  environment.systemPackages = [ pkgs.seahorse ];

  # enable keyring service
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gcr-ssh-agent.enable = true;
}
