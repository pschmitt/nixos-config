# Join Tailscale next to NetBird, so a worker stays reachable when one of the
# two overlays (or its coordination service) is down. The auth key arrives in
# the OpenStack user-data ({"tailscale_auth_key": "tskey-auth-..."}) like the
# NetBird setup key: ephemeral, single use, short-lived and tagged
# tag:rworker, so the copy left in the metadata service is worthless once the
# worker has registered, and the node disappears from the tailnet by itself.
#
# Independent of rworker-netbird-up on purpose: a NetBird join that fails or
# hangs must not delay this one, and the other way round. A missing key
# (control host from before the feature) or a failed join is only logged.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscale = lib.getExe config.services.tailscale.package;
in
{
  services.tailscale = {
    enable = true;
    # Direct paths; DERP relays still work with the port closed upstream.
    openFirewall = true;
    useRoutingFeatures = "none";
  };

  systemd.services.rworker-tailscale-up = {
    description = "Register this worker with Tailscale using the user-data auth key";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "tailscaled.service" ];
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnused
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Shown in the serial console log next to the NetBird join.
      StandardError = "journal+console";
      RuntimeDirectory = "rworker-tailscale";
      RuntimeDirectoryMode = "0700";
      # Never hold up the boot or a shutdown for a coordination server.
      TimeoutStartSec = "3min";
    };
    script = ''
      # Same metadata source as rworker-netbird-up (the boot test points it
      # elsewhere through the kernel command line).
      metadata=$(sed -n 's/.*nixbot-worker\.metadata=\([^ ]*\).*/\1/p' /proc/cmdline)
      metadata="''${metadata:-http://169.254.169.254/openstack/latest}"
      fetch() {
        curl -fsS --retry 30 --retry-delay 2 --retry-connrefused "$metadata/$1"
      }
      name=$(fetch meta_data.json | jq -er '.name')
      user_data=$RUNTIME_DIRECTORY/user-data
      fetch user_data > "$user_data"

      key=$RUNTIME_DIRECTORY/auth-key
      if ! jq -er '.tailscale_auth_key // empty' "$user_data" > "$key"
      then
        echo "rworker: no tailscale_auth_key in the user-data, skipping Tailscale" >&2
        rm -f "$user_data" "$key"
        exit 0
      fi
      rm -f "$user_data"

      if timeout 150 ${tailscale} up \
        --auth-key "file:$key" \
        --hostname "$name" \
        --accept-dns=false \
        --accept-routes=false \
        --ssh=false ${lib.escapeShellArgs config.services.tailscale.extraUpFlags}
      then
        echo "rworker: joined Tailscale as $name" >&2
      else
        echo "rworker: Tailscale join failed, NetBird may still work" >&2
      fi
      rm -f "$key"
    '';
  };

  # SSH (for the nixbot host and the agents) is reachable over the overlays only.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
}
