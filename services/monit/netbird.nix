{
  config,
  pkgs,
  lib,
  ...
}:
let
  netbird = config.services.netbird.clients.netbird-io.wrapper;
  netbirdBin = lib.getExe netbird;

  netbirdStatus = pkgs.writeShellApplication {
    name = "netbird-status";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      export HOME=/var/lib/netbird-netbird-io # prevent warning about HOME not being set

      if ${netbirdBin} status | grep -q "NeedsLogin"
      then
        echo "Netbird login required" >&2
        exit 1
      fi

      # Display status info
      ${netbirdBin} status
    '';
  };

  netbirdHostname = pkgs.writeShellApplication {
    name = "netbird-hostname";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      export HOME=/var/lib/netbird-netbird-io # prevent warning about HOME not being set

      NB_HOSTNAME=$(${netbirdBin} status --json | jq -er '.fqdn | split(".")[0]')
      NB_HOSTNAME_EXPECTED="${config.networking.hostName}"

      if [[ $NB_HOSTNAME != "$NB_HOSTNAME_EXPECTED" ]]
      then
        echo "Netbird hostname $NB_HOSTNAME != $NB_HOSTNAME_EXPECTED" >&2
        exit 1
      fi

      # Display hostname info
      echo "Netbird hostname: $NB_HOSTNAME"
    '';
  };

  interfaceIsUp = pkgs.writeShellScript "interface-is-up" ''
    INTERFACE="$1"

    # Display interface information
    ${pkgs.iproute2}/bin/ip -brief addr show "$INTERFACE"

    ${pkgs.iproute2}/bin/ip --json link show "$INTERFACE" | \
      ${pkgs.jq}/bin/jq -er '.[0].flags | index("UP")' >/dev/null
  '';

in
{
  services.monit.checks = {
    "netbird login" = {
      type = "program";
      path = lib.getExe netbirdStatus;
      group = [
        "network"
        "netbird"
      ];
      restartProgram = "${netbirdBin} up";
      # NOTE: Program checks run async: monit evaluates the *previous* run's
      # exit code each cycle. With a bare "then restart" a single transient
      # failure restarts the service, the next run executes while it is still
      # coming up, fails and restarts it again -- forever.
      conditions = ''
        if status != 0 for 2 cycles then restart
        # recovery
        else if succeeded then exec "${pkgs.coreutils}/bin/true"

        if 5 restarts within 10 cycles then alert
      '';
    };

    "netbird hostname" = {
      type = "program";
      path = lib.getExe netbirdHostname;
      group = [
        "network"
        "netbird"
      ];
      conditions = "if status != 0 then alert";
    };

    "netbird interface" = {
      type = "program";
      path = "${interfaceIsUp} nb-netbird-io";
      group = [
        "network"
        "netbird"
      ];
      dependsOn = [ "netbird login" ];
      restartUnit = "netbird-netbird-io-autoconnect";
      # NOTE: "for 2 cycles" avoids restart loops (see "netbird login" above)
      conditions = ''
        if status != 0 for 2 cycles then restart
        # recovery
        else if succeeded then exec "${pkgs.coreutils}/bin/true"
        if 5 restarts within 10 cycles then alert
      '';
    };

    # FIXME A `check network` on nb-netbird-io does not reliably tell when the
    # interface is up, probably because its operstate is UNKNOWN. But then:
    # why does this not impact the tailscale interface?!
    # See: ip -j link  | jq '.[] | select(.ifname | test("netbird|tailsc"))'
  };
  systemd.services.monit.after = [
    "netbird-netbird-io.service"
  ];
}
