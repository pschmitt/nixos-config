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

  systemd.services.nixbot-worker-netbird-up = {
    description = "Register this worker with NetBird using the user-data setup key";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "netbird-${client}.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "netbird-${client}.service" ];
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "nixbot-worker-netbird";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      metadata=http://169.254.169.254/openstack/latest
      fetch() {
        curl -fsS --retry 30 --retry-delay 2 --retry-connrefused "$metadata/$1"
      }
      name=$(fetch meta_data.json | jq -er '.name')
      user_data=$RUNTIME_DIRECTORY/user-data
      fetch user_data > "$user_data"

      # Optional SSH keys for the agent user (ad-hoc workers).
      install -d -m 0755 /run/nixbot-worker/authorized_keys
      jq -r '.agent_authorized_keys // [] | .[]' "$user_data" \
        > /run/nixbot-worker/authorized_keys/agent
      chmod 0644 /run/nixbot-worker/authorized_keys/agent

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
