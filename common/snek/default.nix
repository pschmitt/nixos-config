{ pkgs, ... }: {
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;  # cli + gui
    enableExcludeWrapper = true;
  };
}
