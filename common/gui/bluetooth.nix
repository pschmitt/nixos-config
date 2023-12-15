{ pkgs, ... }: {
  hardware.bluetooth = {
    enable = true;
    # settings = {
    #   General = {
    #     Enable = "Source,Sink,Media,Socket";
    #   };
    # };
  };

  services.blueman.enable = true;

  # NOTE The bash wrapping here makes not sense but is sadly required to pass
  # the udev check that runs on build time and verifies actively if all the
  # referenced scripts/path exist
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", ATTR{name}=="Jabra Elite 8 Active (AVRCP)", \
    RUN+="${pkgs.zsh}/bin/zsh -c \"/home/pschmitt/bin/udev.sh bluetooth j2\""
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
