{ pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings = {
      dns_enabled = true;
    };
    autoPrune = {
      enable = true;
    };
  };

  # The podman NixOS module only opens the host firewall for aardvark-dns on
  # the *default* network's bridge (podman0 - "containers cannot reach
  # aardvark-dns otherwise"). Anything that creates its own per-run network
  # (e.g. a Forgejo/Gitea Actions runner, one bridge per job) gets a
  # differently-numbered bridge every time, so its containers can't resolve
  # any hostname unless we open the same port for every podman-managed
  # bridge, not just podman0.
  networking.firewall.extraInputRules = ''
    iifname "podman*" udp dport 53 accept
    iifname "podman*" tcp dport 53 accept
  '';

  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}
