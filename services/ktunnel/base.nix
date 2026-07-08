# Shared user/group/state-dir for every ktunnel-expose instance on a host.
# Imported by both services/inet-proxy.nix and services/xmr/ktunnel-xmrig-proxy.nix.
# Safe to import from multiple modules: NixOS merges identical option
# definitions without conflict, and this file only ever defines these once
# in practice since it's the single source both modules pull from.
{
  users.groups.ktunnel = { };
  users.users.ktunnel = {
    group = "ktunnel";
    isSystemUser = true;
    description = "ktunnel k8s tunnel service account";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/ktunnel 0700 ktunnel ktunnel - -"
  ];
}
