{ pkgs, config, ... }: {
  # TODO Define password with agenix
  users.users.pschmitt = {
    uid = 1000;
    isNormalUser = true;
    description = "Philipp Schmitt";
    extraGroups = [
      "adbusers"
      "docker"
      "input"
      "libvirtd"
      "mlocate"
      "networkmanager"
      "pschmitt"
      "uinput" # for *dotool
      "video"
      "wheel"
      "wireshark"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # hass-fnuc
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7"
    ];
    shell = if config.custom.server then pkgs.bash else pkgs.zsh;
  };
}
