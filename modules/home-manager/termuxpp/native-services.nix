{ lib, pkgs, ... }:
{
  # The guest's runit sshd serves port 2222. The native Termux openssh service
  # left over from the native bundle era used the same port: whenever a native
  # login shell started termux-services' runsvdir it took the port and SSH
  # landed outside the guest. runit's down file keeps it off, and survives
  # openssh package upgrades (they only replace run).
  home.activation.disableNativeSshd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    case "''${NIXPP_RUNTIME:-}" in
      /android/*/files/home/.local/share/termuxpp-nix)
        nativeSshd="''${NIXPP_RUNTIME%/home/.local/share/termuxpp-nix}/usr/var/service/sshd"
        if [[ -d $nativeSshd && ! -e $nativeSshd/down ]]
        then
          run ${pkgs.coreutils}/bin/touch "$nativeSshd/down"
        fi
        if [[ -d $nativeSshd ]]
        then
          # Stop a running native instance; sv fails fast when no runsv owns it.
          run ${pkgs.runit}/bin/sv down "$nativeSshd" 2>/dev/null || true
        fi
        unset nativeSshd
        ;;
    esac
  '';
}
