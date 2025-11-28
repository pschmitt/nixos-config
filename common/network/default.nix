{ pkgs, ... }:
{
  imports = [
    ./dns.nix
    ./netbird.nix
    ./snek/proxychains.nix
    ./tailscale.nix
    ./zerotier.nix
  ];

  environment.systemPackages = with pkgs; [
    bind # dig
    (pkgs.curl.override {
      http3Support = true;
      ldapSupport = true;
      websocketSupport = true;
    })
    fping
    nethogs
    nmap
    ookla-speedtest
    openssl
    socat
    tcpdump
    wget
    wireguard-tools
  ];

  security.wrappers = {
    fping = {
      source = "${pkgs.fping}/bin/fping";
      setuid = true;
      owner = "root";
      group = "root";
    };
  };
}
