{
  # Keep journal growth bounded on the small root filesystem.
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemKeepFree=5G
  '';
}
