{ config, pkgs, ... }:
{
  sops.secrets."netdata/claimToken" = { };

  services.netdata = {
    enable = true;
    python.recommendedPythonPackages = true;
    # https://github.com/NixOS/nixpkgs/issues/277748
    package = pkgs.netdata.override { withCloud = true; };
    claimTokenFile = "${config.sops.secrets."netdata/claimToken".path}";
  };
}
