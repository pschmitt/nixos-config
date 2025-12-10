{
  config,
  lib,
  pkgs,
  ...
}:
let
  instanceName = "main";
  autheliaDomain = "auth.${config.domains.main}";
  autheliaUser = "authelia-${instanceName}";
  autheliaGroup = autheliaUser;
  autheliaService = "authelia-${instanceName}.service";
  autheliaPort = 28843;
  stateDir = "/var/lib/${autheliaUser}";
  runtimeStateDir = "/run/authelia";
  containerServicesEnabled = lib.attrByPath [ "custom" "containerServices" "enable" ] false config;
  managedTrustedNetworksFile = "${runtimeStateDir}/trusted-networks.yml";
  dynamicTrustedNetworksFile =
    if containerServicesEnabled then
      "/run/container-services/authelia-trusted-networks.yml"
    else
      managedTrustedNetworksFile;
  trustedHosts = [ "turris.${config.domains.main}" ];
  trustedHostsEnv = lib.concatStringsSep " " trustedHosts;
  secretsAttrs = owner: {
    inherit (config.custom) sopsFile;
    inherit owner;
    group = autheliaGroup;
    mode = "0400";
    restartUnits = [ autheliaService ];
  };
  bypassNetworks = [
    "127.0.0.1/32"
    "::1/128"
    "100.64.0.0/10"
  ];
  autheliaLocalNetworksEnv = lib.concatStringsSep "\n" bypassNetworks;
  trustedNetworksUpdaterScript = pkgs.writeShellScript "authelia-trusted-networks" (
    builtins.readFile ./scripts/update-container-trusted-networks.sh
  );
  autheliaSettings = {
    server.address = "tcp://:${toString autheliaPort}/";
    theme = "auto";
    default_2fa_method = "webauthn";
    session.cookies = [
      {
        domain = config.domains.main;
        authelia_url = "https://${autheliaDomain}";
      }
    ];
    authentication_backend.file = {
      inherit (config.sops.secrets."authelia/users-database") path;
      watch = false;
    };
    storage.local.path = "${stateDir}/db.sqlite3";
    webauthn = {
      disable = false;
      enable_passkey_login = true;
      display_name = "Authelia";
      selection_criteria = {
        attachment = "platform";
        discoverability = "preferred";
        user_verification = "preferred";
      };
    };
    notifier.disable_startup_check = false;
    access_control = {
      default_policy = "two_factor";
      networks = lib.mkIf (dynamicTrustedNetworksFile == null) [
        {
          name = "local";
          networks = bypassNetworks;
        }
      ];
      rules = [
        {
          policy = "bypass";
          domain = [ autheliaDomain ];
        }
        {
          policy = "bypass";
          networks = [
            "local"
          ]
          ++ lib.optional (dynamicTrustedNetworksFile != null) "container-services-trusted";
          domain = [ "*.${config.domains.main}" ];
        }
        {
          policy = "one_factor";
          domain = [ "blobs.${config.domains.main}" ];
          subject = [ "group:admin" ];
        }
        {
          policy = "one_factor";
          domain = [ "blobs.${config.domains.main}" ];
          resources = [
            "^/private/?$"
            "^/private/.*$"
          ];
          subject = [
            "group:admin"
            "group:github-actions"
          ];
        }
        # Deny any other request to blobs
        # {
        #   policy = "deny";
        #   domain = [ "blobs.${config.domains.main}" ];
        #   subject = [ "group:github-actions" ];
        # }
      ];
    };
  };
in
{
  sops = {
    secrets = {
      "authelia/jwt-secret" = secretsAttrs autheliaUser;
      "authelia/storage-encryption-key" = secretsAttrs autheliaUser;
      "authelia/users-database" = secretsAttrs autheliaUser;
      "authelia/duo/hostname" = secretsAttrs autheliaUser;
      "authelia/duo/integration-key" = secretsAttrs autheliaUser;
      "authelia/duo/secret-key" = secretsAttrs autheliaUser;
      "authelia/smtp/address" = secretsAttrs autheliaUser;
      "authelia/smtp/username" = secretsAttrs autheliaUser;
      "authelia/smtp/password" = secretsAttrs autheliaUser;
      "authelia/smtp/sender" = secretsAttrs autheliaUser;
    };
    templates = {
      "authelia/duo.yml" = {
        content = ''
          duo_api:
            disable: false
            hostname: ${config.sops.placeholder."authelia/duo/hostname"}
            integration_key: ${config.sops.placeholder."authelia/duo/integration-key"}
            secret_key: ${config.sops.placeholder."authelia/duo/secret-key"}
            enable_self_enrollment: true
        '';
        owner = autheliaUser;
        group = autheliaGroup;
        mode = "0400";
        restartUnits = [ autheliaService ];
      };
      "authelia/smtp.yml" = {
        content = ''
          notifier:
            smtp:
              address: ${config.sops.placeholder."authelia/smtp/address"}
              username: ${config.sops.placeholder."authelia/smtp/username"}
              password: ${config.sops.placeholder."authelia/smtp/password"}
              sender: ${config.sops.placeholder."authelia/smtp/sender"}
        '';
        owner = autheliaUser;
        group = autheliaGroup;
        mode = "0400";
        restartUnits = [ autheliaService ];
      };
    };
  };

  services = {
    authelia.instances.${instanceName} = {
      enable = true;
      user = autheliaUser;
      group = autheliaGroup;
      settingsFiles = lib.optional (dynamicTrustedNetworksFile != null) dynamicTrustedNetworksFile ++ [
        config.sops.templates."authelia/duo.yml".path
        config.sops.templates."authelia/smtp.yml".path
      ];
      secrets = {
        jwtSecretFile = config.sops.secrets."authelia/jwt-secret".path;
        storageEncryptionKeyFile = config.sops.secrets."authelia/storage-encryption-key".path;
      };
      settings = autheliaSettings;
    };

    nginx.virtualHosts.${autheliaDomain} = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString autheliaPort}/";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "authelia" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart ${autheliaService}"
        if failed port ${toString autheliaPort} then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  systemd = lib.mkIf (!containerServicesEnabled) {
    tmpfiles.rules = [
      "d ${runtimeStateDir} 0755 root root -"
    ];

    services.authelia-update-trusted-networks = {
      description = "Update Authelia trusted networks allowlist";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.dnsutils
        pkgs.diffutils
        pkgs.systemd
      ];
      script = ''
        set -eu

        resolver_script=${lib.escapeShellArg trustedNetworksUpdaterScript}
        export AUTHELIA_OUTPUT=${lib.escapeShellArg managedTrustedNetworksFile}
        export AUTHELIA_UNITS=${lib.escapeShellArg autheliaService}
        export TRUSTED_HOSTS=${lib.escapeShellArg trustedHostsEnv}
        export AUTHELIA_LOCAL_NETWORKS=${lib.escapeShellArg autheliaLocalNetworksEnv}

        "$resolver_script"
      '';
    };

    timers.authelia-update-trusted-networks = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "5m";
      };
    };
  };
}
