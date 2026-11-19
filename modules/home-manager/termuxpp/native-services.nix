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
        # The retired native-era Termux:Boot script (yadm-config 508b1c7c)
        # survives on some phones and deletes that down file on every boot.
        legacyBoot="''${NIXPP_RUNTIME%/home/.local/share/termuxpp-nix}/home/.config/termuxpp/boot/start-services.sh"
        if [[ -f $legacyBoot ]] && ${pkgs.gnugrep}/bin/grep -q 'SVDIR/sshd/down' "$legacyBoot"
        then
          run ${pkgs.coreutils}/bin/mkdir -p "''${legacyBoot%/.config/*}/.cache/termuxpp-retired"
          run ${pkgs.coreutils}/bin/mv -f -- "$legacyBoot" "''${legacyBoot%/.config/*}/.cache/termuxpp-retired/boot-start-services.sh"
        fi
        unset legacyBoot
        ;;
    esac
  '';

  # Home Assistant starts and stops sshd through Tasker, which may only run
  # native scripts from its allowlisted directory. The launcher drives the
  # guest's runit sshd instead of starting a separate, unsupervised one.
  home.activation.installManagedSshdLauncher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    case "''${NIXPP_RUNTIME:-}" in
      /android/*/.local/share/termuxpp-nix)
        sshdLauncher="''${NIXPP_RUNTIME%/.local/share/termuxpp-nix}/.config/termuxpp/tasker/set-managed-sshd"
        run ${pkgs.coreutils}/bin/install -Dm700 ${./scripts/set-managed-sshd.sh} "$sshdLauncher.new"
        run ${pkgs.coreutils}/bin/mv -fT -- "$sshdLauncher.new" "$sshdLauncher"
        unset sshdLauncher
        ;;
    esac
  '';
}
