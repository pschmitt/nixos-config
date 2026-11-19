{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "termuxpp-setup-permissions";
      # rish and nixpp come from the guest profile.
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
        pkgs.util-linux
      ];
      text = builtins.readFile ./scripts/setup-permissions.sh;
    })
  ];
}
