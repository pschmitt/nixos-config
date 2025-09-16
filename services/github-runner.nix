{ config, pkgs, ... }:
{

  sops.secrets."github-runners/nixos-config/token" = {
    sopsFile = config.custom.sopsFile;
  };

  services.github-runners.nixos-config = {
    enable = true;

    name = config.networking.hostName;
    replace = true;
    ephemeral = false;

    url = "https://github.com/pschmitt/nixos-config";
    tokenFile = config.sops.secrets."github-runners/nixos-config/token".path;

    noDefaultLabels = false;
    extraLabels = [
      "self-hosted"
      "linux"
      "nixos"
    ];

    extraPackages = with pkgs; [
      git
      jq
      nix
      openssh
    ];

    # workDir = "/var/lib/github-runner/work";
  };
}
