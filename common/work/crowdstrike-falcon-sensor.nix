{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.falcon-sensor.nixosModules.default ];

  services.falcon-sensor = {
    enable = true;
    cid = "00000000000000000000000000000000-00";
    kernelPackages = null;
  };

  sops.secrets."crowdstrike/customerId" = {
    sopsFile = ../../secrets/shared.sops.yaml;
  };

  systemd.services.falcon-sensor = {
    # Let's just not start this garbage service automatically
    wantedBy = lib.mkForce [ ];

    serviceConfig = {
      # upstream uses /var/run/falcond.pid - systemd complains about that:
      # PIDFile= references a path below legacy directory /var/run/, updating /var/run/falcond.pid → /run/falcond.pid; please update the unit file accordingly.
      PIDFile = lib.mkForce "/run/falcond.pid";

      ExecStartPre = lib.mkForce [
        (pkgs.writeScript "falcon-init" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail
          ln -sf ${pkgs.falcon-sensor-unwrapped}/opt/CrowdStrike/* /opt/CrowdStrike/
          ${pkgs.falcon-sensor}/bin/falconctl -s --trace=debug

          if [ -f ${config.sops.secrets."crowdstrike/customerId".path} ]; then
            CID=$(cat ${config.sops.secrets."crowdstrike/customerId".path})
            ${pkgs.falcon-sensor}/bin/falconctl -s --cid="$CID" -f
          else
            echo "CID secret not found at ${config.sops.secrets."crowdstrike/customerId".path}!"
            exit 1
          fi

          ${pkgs.falcon-sensor}/bin/falconctl -g --cid
        '')
      ];
    };
  };

  nixpkgs.overlays = [
    (final: prev: {
      falcon-sensor = prev.falcon-sensor-wiit;
      falcon-sensor-unwrapped = prev.falcon-sensor-wiit.unwrapped;
    })
  ];
}
