# ADB (Android Debug Bridge) USB access. systemd's built-in ADB udev rule
# (which replaced nixpkgs' now-removed android-udev-rules package) already
# tags a recognized ADB interface with ENV{ID_DEBUG_APPLIANCE}=="android"
# and TAG+="uaccess", but uaccess only grants an ACL to a session actually
# sat at a seat -- headless hosts (e.g. fnuc/lrz) never claim one, so the
# ACL never lands even though the tag is correct. Grant access by group
# instead; this is a no-op elsewhere and harmless on desktop/laptop hosts
# where uaccess already works fine.
{ config, ... }:
{
  users.groups.adbusers = { };
  users.users.${config.mainUser.username}.extraGroups = [ "adbusers" ];

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ENV{ID_DEBUG_APPLIANCE}=="android", MODE="0660", GROUP="adbusers"
  '';
}
