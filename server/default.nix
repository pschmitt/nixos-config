# See also: https://github.com/nix-community/srvos
{ pkgs, lib, ... }: {
  imports = [
    ../common/global

    ../misc/luks-ssh-unlock.nix
    ../misc/git-clone-nixos-config.nix
    ../misc/users/github-actions.nix
    ../misc/users/nix-remote-builder.nix

    ../misc/git-clone-nixos-config.nix
    ../misc/luks-ssh-unlock.nix
    ../misc/users/github-actions.nix
    ../misc/users/nix-remote-builder.nix
  ];

  custom.server = true;
  custom.useBIOS = true;

  # Write logs to console
  # https://github.com/nix-community/srvos/blob/main/nixos/common/serial.nix
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  networking.useNetworkd = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    curl
    dnsutils
    gitMinimal
    htop
    jq
    tmux
  ];
}
