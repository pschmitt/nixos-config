# Join NetBird with the one-off setup key the autoscaler (or rworker)
# puts into the OpenStack user-data ({"netbird_setup_key": "...",
# "agent_authorized_keys": ["ssh-ed25519 ..."]}; the keys are optional). The key is ephemeral,
# single use and short-lived, so the copy left in the metadata service is
# worthless once the worker has registered.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  client = "netbird-io";
  inherit (config.services.netbird.clients.${client}) interface wrapper;
in
{
  services.netbird = {
    enable = true;
    clients = lib.mkForce {
      ${client} = {
        port = 51820;
        environment = {
          NB_ALLOW_SERVER_SSH = "false";
          NB_DISABLE_SSH_CONFIG = "true";
        };
      };
    };
  };

  systemd.services.rworker-netbird-up = {
    description = "Register this worker with NetBird using the user-data setup key";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "netbird-${client}.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "netbird-${client}.service" ];
    path = [
      config.systemd.package
      pkgs.coreutils
      pkgs.curl
      pkgs.gnused
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Without NetBird nobody can log in: show failures in the serial
      # console log (`openstack console log show`).
      StandardError = "journal+console";
      RuntimeDirectory = "rworker-netbird";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      # nixbot-worker.metadata=URL on the kernel command line points
      # elsewhere (the boot test's fake metadata service).
      metadata=$(sed -n 's/.*nixbot-worker\.metadata=\([^ ]*\).*/\1/p' /proc/cmdline)
      metadata="''${metadata:-http://169.254.169.254/openstack/latest}"
      fetch() {
        curl -fsS --retry 30 --retry-delay 2 --retry-connrefused "$metadata/$1"
      }
      fetch meta_data.json > "$RUNTIME_DIRECTORY/meta_data.json"
      name=$(jq -er '.name' "$RUNTIME_DIRECTORY/meta_data.json")
      # The OpenStack name (adhoc-..., rworker-...) as hostname, for
      # prompts, logs and NetBird. Transient only: the static hostname lives
      # in the read-only /etc, and failing here must not stop the join.
      hostnamectl hostname --transient "$name" \
        || echo "could not set the hostname to $name" >&2

      # The worker's metadata as of this boot, for anyone on the worker
      # (no setup key ID; the key itself is only in the user-data).
      install -d -m 0755 /run/rworker
      jq --arg system "$(readlink -f /run/current-system)" \
        --arg booted "$(date -u +%FT%TZ)" '{
          source: "initial",
          name, uuid, availability_zone,
          booted: $booted,
          system: $system,
          meta: ((.meta // {}) | del(.setup_key_id))
        }' "$RUNTIME_DIRECTORY/meta_data.json" > /run/rworker/metadata.json
      chmod 0644 /run/rworker/metadata.json
      # Progress marker for the console log (and the boot test).
      echo "rworker: named $name, metadata in /run/rworker/metadata.json" >&2
      user_data=$RUNTIME_DIRECTORY/user-data
      fetch user_data > "$user_data"

      # Optional SSH keys for the agent user (ad-hoc workers).
      install -d -m 0755 /run/ssh-authorized-keys
      jq -r '.agent_authorized_keys // [] | .[]' "$user_data" \
        > /run/ssh-authorized-keys/agent
      chmod 0644 /run/ssh-authorized-keys/agent

      key=$RUNTIME_DIRECTORY/setup-key
      jq -er '.netbird_setup_key' "$user_data" > "$key"
      rm -f "$user_data"
      ${lib.getExe wrapper} up --setup-key-file "$key" --hostname "$name"
      rm -f "$key"
    '';
  };

  # SSH (for the nixbot host) is reachable over NetBird only.
  networking.firewall.interfaces.${interface}.allowedTCPPorts = [ 22 ];
}
