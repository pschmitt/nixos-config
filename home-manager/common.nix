_: {
  programs.home-manager.enable = true;

  systemd.user.startServices = "sd-switch";

  home.preferXdgDirectories = true;
  xdg.userDirs.setSessionVariables = true;
}
