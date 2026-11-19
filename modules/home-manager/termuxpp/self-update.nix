{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "termuxpp-self-update";
      # termux-am comes from the guest profile.
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ];
      text = builtins.readFile ./scripts/self-update.sh;
    })
  ];
}
