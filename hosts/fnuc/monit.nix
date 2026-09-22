{
  lib,
  pkgs,
  ...
}:
let
  thermals = pkgs.writeShellApplication {
    name = "fnuc-thermals";
    runtimeInputs = [
      pkgs.jq
      pkgs.lm_sensors
    ];
    text = builtins.readFile ./scripts/thermals.sh;
  };

  fnucNetworkHealth = pkgs.writeShellScript "fnuc-network-health" ''
    set -o pipefail

    failures=()

    if ${pkgs.systemd}/bin/journalctl -k -b -g e1000e -o cat --no-pager \
      | ${pkgs.gnugrep}/bin/grep -Eiq 'detected hardware unit hang|netdev watchdog|tx timeout'
    then
      failures+=("e1000e hardware hang recorded in the current boot")
    fi

    if ! ${pkgs.ethtool}/bin/ethtool --show-eee eno1 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -Fq 'EEE status: disabled'
    then
      failures+=("EEE is not disabled on eno1")
    fi

    if ! ${pkgs.iputils}/bin/ping -I hass-br0 -c 1 -W 2 10.5.0.1 >/dev/null 2>&1
    then
      failures+=("10.5.0.1 is unreachable through hass-br0")
    fi

    if [[ ''${#failures[@]} -eq 0 ]]
    then
      printf '%s\n' 'eno1 and hass-br0 network health is good'
      exit 0
    fi

    printf '%s\n' "''${failures[@]}" >&2
    exit 1
  '';
in
{
  services.monit.config = lib.mkAfter ''
    check program "thermals" with path "${thermals}/bin/fnuc-thermals 90"
      if status > 0 for 5 cycles then alert

    # The e1000e driver can report carrier up while its TX ring is wedged.
    # Keep this alert-only: recovery may require diagnosis or a reboot.
    check program "fnuc wired network health" with path "${fnucNetworkHealth}"
      group network
      if status > 0 for 2 cycles then alert
  '';
}
