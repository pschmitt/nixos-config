{
  hardware.bluetooth = {
    enable = true;
  };

  # Blueman more or less breaks a2dp profile selection
  # services.blueman.enable = true;

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
