{ pkgs, ... }:
{
  imports = [
    ./network.nix
    ./netbird.nix
    ./tailscale.nix
    ./zerotier.nix
  ];

  environment.systemPackages = with pkgs; [
    bind # dig
    curl
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
