{
  config,
  pkgs,
  lib,
  ...
}:
let
  netbirdStatus = pkgs.writeShellScript "netbird-status" ''
    export PATH="/run/current-system/sw/bin:${pkgs.gnugrep}:$PATH"
    NB_BIN="netbird-netbird-io"
    export HOME="/var/lib/$NB_BIN" # prevent warning about HOME not being set

    if "$NB_BIN" status | \
      grep -q "NeedsLogin"
    then
      echo "Netbird login required" >&2
      exit 1
    fi

    # Display status info
    netbird-netbird-io status
    exit 0
  '';

  netbirdHostname = pkgs.writeShellScript "netbird-hostname" ''
    export PATH="/run/current-system/sw/bin:${pkgs.jq}:$PATH"
    NB_BIN="netbird-netbird-io"
    export HOME="/var/lib/$NB_BIN" # prevent warning about HOME not being set

    NB_HOSTNAME=$("$NB_BIN" status --json | \
      jq -er '.fqdn | split(".")[0]')
    NB_HOSTNAME_EXPECTED="${config.networking.hostName}"

    if [[ $NB_HOSTNAME != $NB_HOSTNAME_EXPECTED ]]
    then
      echo "Netbird hostname $NB_HOSTNAME != $NB_HOSTNAME_EXPECTED" >&2
      exit 1
    fi

    # Display hostname info
    echo "Netbird hostname: $NB_HOSTNAME"
    exit 0
  '';

  interfaceIsUp = pkgs.writeShellScript "interface-is-up" ''
    INTERFACE="$1"

    # Display interface information
    ${pkgs.iproute2}/bin/ip -brief addr show "$INTERFACE"

    ${pkgs.iproute2}/bin/ip --json link show "$INTERFACE" | \
      ${pkgs.jq}/bin/jq -er '.[0].flags | index("UP")' >/dev/null
  '';

  monitNetbird = ''
    check program "netbird login" with path "${netbirdStatus}"
      group "network"
      restart program = "/run/current-system/sw/bin/netbird-netbird-io up"
      if status != 0 then restart
      # recovery
      else if succeeded then exec "${pkgs.coreutils}/bin/true"

      if 5 restarts within 10 cycles then alert

    check program "netbird hostname" with path "${netbirdHostname}"
      group "network"
      if status != 0 then alert

    check program "netbird interface" with path "${interfaceIsUp} nb-netbird-io"
      group "network"
      depends on "netbird login"
      restart program = "${pkgs.systemd}/bin/systemctl restart netbird-netbird-io-autoconnect"
      if status != 0 then restart
      # recovery
      else if succeeded then exec "${pkgs.coreutils}/bin/true"
      if 5 restarts within 10 cycles then alert

    # FIXME Below check seems to be able to tell reliably when the interface is
    # up. It's probably due to the fact that the operstate of the netbird
    # interface is UNKNOWN.
    # But then: why does this not impact the tailscale interface?!
    # See: ip -j link  | jq '.[] | select(.ifname | test("netbird|tailsc"))'
    # check network netbird with interface nb-netbird-io
    #   group "network"
    #   depends on "netbird login"
    #   restart program = "${pkgs.systemd}/bin/systemctl restart netbird-netbird-io"
    #   if link down for 2 cycles then restart
    #   if 5 restarts within 10 cycles then alert
  '';
in
{
  # monit configuration
  services.monit.config = lib.mkAfter monitNetbird;
  systemd.services.monit.after = [
    "netbird-netbird-io.service"
  ];
}
