{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  poorInstallerWeb = pkgs.python313Packages.buildPythonPackage {
    # The project metadata is named poor_tools_web. Using its normalized name
    # keeps the Nixpkgs Python metadata check aligned with that metadata.
    pname = "poor-tools-web";
    version = "0.1.0";
    pyproject = true;
    src = inputs.poor-tools;

    nativeBuildInputs = [
      pkgs.python313Packages.hatchling
      pkgs.makeWrapper
    ];

    propagatedBuildInputs = with pkgs.python313Packages; [
      fastapi
      uvicorn
    ];

    postInstall = ''
      wrapProgram $out/bin/poor-installer-web \
        --set POOR_TOOLS_VERSION ${inputs.poor-tools.shortRev or "source"}
    '';

    pythonImportsCheck = [ "poor_installer_web" ];
  };
in
{
  imports = [ inputs.poor-tools.nixosModules.default ];

  systemd.services.poor-installer-web.serviceConfig.ExecStart =
    lib.mkForce "${poorInstallerWeb}/bin/poor-installer-web";

  services = {
    poor-installer-web.enable = true;

    nginx.virtualHosts =
      let
        nginxConfig = {
          enableACME = true;
          # FIXME https://github.com/NixOS/nixpkgs/issues/210807
          acmeRoot = null;
          forceSSL = false; # disabled on purpose! tls is a luxury
          addSSL = true; # required to actually respond to https requests

          locations."/" = {
            proxyPass = "http://${toString config.services.poor-installer-web.bindHost}:${toString config.services.poor-installer-web.bindPort}";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
        };
      in
      {
        "poor.tools" = nginxConfig;
        "poor.${config.domains.main}" = nginxConfig;
      };

    monit.config = lib.mkAfter ''
      check host "poor-installer-web" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart poor-installer-web.service"
        if failed
          port ${toString config.services.poor-installer-web.bindPort}
          protocol http
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };
}
