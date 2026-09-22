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
  secretsAttrs =
    owner:
    config.sops.mkHostSecret {
      inherit owner;
      group = autheliaGroup;
      mode = "0400";
      restartUnits = [ autheliaService ];
    };
  # Localhost + the Netbird/Tailscale CGNAT mesh are the only networks allowed
  # to bypass Authelia. We deliberately do NOT trust any dynamically-resolved
  # host (previously turris.${config.domains.main}): its A record is the home
  # WAN IP, so hairpinned/NAT-reflected traffic appeared "trusted" and skipped
  # auth entirely. The mesh range can't be spoofed that way.
  bypassNetworks = [
    "127.0.0.1/32"
    "::1/128"
    "100.64.0.0/10"
    # Both meshes hand out IPv6 as well, and clients prefer it when it is
    # available -- so without these a browser on the mesh arrives from a ULA
    # address and the bypass above silently never applies. Tailscale's own /48
    # and this Netbird network's routed /64; deliberately that /64 rather than
    # Netbird's whole /48, to keep the bypass as narrow as what is routed.
    "fd7a:115c:a1e0::/48"
    "fd8d:fa54:9081:c944::/64"
  ];
  # Every <service>.<host>.<mesh domain> name, in one rule. Those names only
  # resolve to mesh addresses, but nginx answers on 0.0.0.0, so a request can
  # still arrive at such a vhost by sending its SNI to the WAN address -- the
  # bypass is therefore decided by source network, not by the hostname, and an
  # off-mesh request falls through to the rules below like any other.
  meshDomainRegex =
    "^([^.]+\\.)+("
    + lib.concatStringsSep "|" (map (d: lib.replaceStrings [ "." ] [ "\\." ] d) config.domains.mesh)
    + ")$";
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
      networks = [
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
      ]
      ++ lib.optional (config.services.authelia.extraTwoFactorDomains != [ ]) {
        # Like extraAuthenticatedDomains, but require the stronger policy for
        # applications whose control plane can execute privileged actions.
        # This precedes the mesh-wide bypass below.
        policy = "two_factor";
        domain = config.services.authelia.extraTwoFactorDomains;
      }
      ++ lib.optional (config.services.authelia.extraAuthenticatedDomains != [ ]) {
        # Some apps have NO login of their own — they use proxy auth (e.g.
        # X-Auth-User from Authelia's Remote-User) or run with
        # AUTHENTICATIONMETHOD=External (fully trusting the proxy). Those
        # domains must be authenticated even on the bypass networks: otherwise
        # the *.${domain} network bypass below would skip auth entirely and
        # leave them wide open to anything on the mesh range. Placed before the
        # bypass so it takes precedence.
        # (HA-app access is unaffected: nginx short-circuits Authelia via the
        # ingress Bearer token before any rule is evaluated.)
        policy = "one_factor";
        domain = config.services.authelia.extraAuthenticatedDomains;
      }
      ++ [
        {
          policy = "bypass";
          networks = [ "local" ];
          domain = [ "*.${config.domains.main}" ];
        }
        {
          # The wildcard above is one label deep, so it does not match the
          # mesh names -- they need their own rule.
          policy = "bypass";
          networks = [ "local" ];
          domain_regex = [ meshDomainRegex ];
        }
      ]
      ++ config.services.authelia.extraAccessControlRules;
    };
  };
in
{
  config.sops = {
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
      # OIDC provider (identity_providers.oidc): the HMAC secret and the JWKS
      # issuer private key are wired via the module's secrets.oidc*File options;
      # the per-client secret hash is rendered into the oidc.yml template below.
      "authelia/oidc-hmac-secret" = secretsAttrs autheliaUser;
      "authelia/oidc-issuer-private-key" = secretsAttrs autheliaUser;
      "authelia/oidc-audiobookshelf-secret-hash" = secretsAttrs autheliaUser;
      "authelia/oidc-filebrowser-secret-hash" = secretsAttrs autheliaUser;
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
      # OIDC clients live in their own settings file so the per-client secret
      # hash stays in sops. hmac_secret + jwks come from the module's
      # secrets.oidc*File options; this only adds the clients list. New OIDC
      # apps get another entry here (+ a secret hash + redirect URIs).
      "authelia/oidc.yml" = {
        content = ''
          identity_providers:
            oidc:
              clients:
                - client_id: 'audiobookshelf'
                  client_name: 'Audiobookshelf'
                  client_secret: '${config.sops.placeholder."authelia/oidc-audiobookshelf-secret-hash"}'
                  public: false
                  authorization_policy: 'two_factor'
                  require_pkce: true
                  pkce_challenge_method: 'S256'
                  redirect_uris:
                    # ABS is served under the /audiobookshelf sub-path, so its
                    # redirect_uri carries that prefix; root variants kept as a
                    # fallback in case the sub-path is dropped later.
                    - 'https://abs.${config.domains.main}/audiobookshelf/auth/openid/callback'
                    - 'https://abs.${config.domains.main}/audiobookshelf/auth/openid/mobile-redirect'
                    - 'https://abs.${config.domains.main}/auth/openid/callback'
                    - 'https://abs.${config.domains.main}/auth/openid/mobile-redirect'
                    # Native ABS mobile app (Android/iOS) custom-scheme redirect.
                    - 'audiobookshelf://oauth'
                  scopes:
                    - 'openid'
                    - 'profile'
                    - 'groups'
                    - 'email'
                  response_types:
                    - 'code'
                  grant_types:
                    - 'authorization_code'
                  access_token_signed_response_alg: 'none'
                  userinfo_signed_response_alg: 'none'
                  token_endpoint_auth_method: 'client_secret_basic' # gitleaks:allow (not a secret)
                - client_id: 'filebrowser-quantum'
                  client_name: 'FileBrowser Quantum'
                  client_secret: '${config.sops.placeholder."authelia/oidc-filebrowser-secret-hash"}'
                  public: false
                  authorization_policy: 'two_factor'
                  # FileBrowser Quantum's OIDC client doesn't send a
                  # code_challenge (confirmed by Authelia rejecting the
                  # authorization request with "Clients must include a
                  # 'code_challenge'... but it is missing" once PKCE was
                  # required), unlike audiobookshelf above.
                  require_pkce: false
                  redirect_uris:
                    - 'https://files.${config.domains.main}/api/auth/oidc/callback'
                  scopes:
                    - 'openid'
                    - 'profile'
                    - 'groups'
                    - 'email'
                  response_types:
                    - 'code'
                  grant_types:
                    - 'authorization_code'
                  access_token_signed_response_alg: 'none'
                  userinfo_signed_response_alg: 'none'
                  # FileBrowser Quantum's OIDC client sends the secret via
                  # client_secret_post (confirmed by the token-exchange
                  # error when this was set to client_secret_basic, unlike
                  # audiobookshelf above), not a configurable option there.
                  token_endpoint_auth_method: 'client_secret_post' # gitleaks:allow (not a secret)
        '';
        owner = autheliaUser;
        group = autheliaGroup;
        mode = "0400";
        restartUnits = [ autheliaService ];
      };
    };
  };

  config.services = {
    authelia.instances.${instanceName} = {
      enable = true;
      user = autheliaUser;
      group = autheliaGroup;
      settingsFiles = [
        config.sops.templates."authelia/duo.yml".path
        config.sops.templates."authelia/smtp.yml".path
        config.sops.templates."authelia/oidc.yml".path
      ];
      secrets = {
        jwtSecretFile = config.sops.secrets."authelia/jwt-secret".path;
        storageEncryptionKeyFile = config.sops.secrets."authelia/storage-encryption-key".path;
        # Enables the OIDC provider: HMAC via env, and the module templates the
        # JWKS issuer key into the generated oidc-jwks config file.
        oidcHmacSecretFile = config.sops.secrets."authelia/oidc-hmac-secret".path;
        oidcIssuerPrivateKeyFile = config.sops.secrets."authelia/oidc-issuer-private-key".path;
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
        # Allow auth.brkn.lol to be embedded in the HA sidebar iframe.
        # Authelia sends X-Frame-Options: DENY and frame-ancestors 'none' by
        # default; strip both and replace with a targeted CSP.
        extraConfig = ''
          proxy_hide_header X-Frame-Options;
          proxy_hide_header Content-Security-Policy;
          add_header Content-Security-Policy "default-src 'self'; base-uri 'self'; connect-src 'self'; frame-ancestors 'self' https://ha.${config.domains.main}; frame-src 'none'; object-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline';" always;
        '';
      };
    };

    monit.config = lib.mkAfter ''
      check host "authelia" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart ${autheliaService}"
        if failed port ${toString autheliaPort} for 3 cycles then restart
        if 3 restarts within 15 cycles then alert
    '';
  };
}
