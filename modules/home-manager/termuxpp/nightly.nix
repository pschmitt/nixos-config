{ lib, pkgs, ... }:
let
  maintenance = pkgs.writeShellApplication {
    name = "termuxpp-nightly-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      pkgs.mani
      pkgs.openssh
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/nightly-update.sh;
  };
in
{
  home.packages = [ maintenance ];

  # Tasker runs in Android's native environment. Its allowlisted script cannot
  # link into the guest store, so install the small launcher as a native file.
  home.activation.installNightlyLauncher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    case "''${NIXPP_RUNTIME:-}" in
      /android/*/.local/share/termuxpp-nix)
        nightlyLauncher="''${NIXPP_RUNTIME%/.local/share/termuxpp-nix}/.config/termuxpp/tasker/nightly-update.sh"
        run ${pkgs.coreutils}/bin/install -Dm700 ${./scripts/nightly-launcher.sh} "$nightlyLauncher.new"
        run ${pkgs.coreutils}/bin/mv -fT -- "$nightlyLauncher.new" "$nightlyLauncher"
        unset nightlyLauncher
        ;;
    esac
  '';
}
