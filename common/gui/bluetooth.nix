{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
  };

  # Blueman more or less breaks a2dp profile selection
  # services.blueman.enable = true;

  environment.systemPackages = with pkgs; [ udev-custom-callback ];

  # FIXME This should be part of the udev-custom-callback package
  # But how can we possibly self-reference the script path in the udev rule
  # from the package itself? If we ever fix this then we can uncomment the
  # line below:
  # services.udev.packages = [ pkgs.udev-custom-bt-rules ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", ENV{ID_BUS}=="bluetooth" \
    RUN+="${pkgs.udev-custom-callback}/bin/udev-custom-callback.sh '%p'"
  '';

  # Disable automatic profile selection (headset)
  # https://wiki.archlinux.org/title/PipeWire#Automatic_profile_selection
  # https://pipewire.pages.freedesktop.org/wireplumber/configuration/bluetooth.html
  # FIXME This crashes wireplumber
  # environment.etc = {
  #   "wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
  #     bluetooth_policy.policy["media-role.use-headset-profile"] = false
  #   '';
  # };
}
