{
  config,
  lib,
  pkgs,
  ...
}:
let
  containerName = "browser-mcp-chromium";
  dataDir = "${config.home.homeDirectory}/.local/share/${containerName}/config";
  envFile = config.sops.templates."${containerName}.env".path;

  proxyContainerName = "browser-mcp-traefik";
  proxyDataDir = "${config.home.homeDirectory}/.local/share/${proxyContainerName}";
  proxyEnvFile = config.sops.templates."${proxyContainerName}.env".path;

  primaryDomain = "browser.fnuc.${config.domains.tailscale}";
  aliasDomains = [
    "browser.fnuc.${config.domains.netbird}"
    "browser.fnuc.${config.domains.vpn}"
  ];
  allDomains = [ primaryDomain ] ++ aliasDomains;
  domainRules = lib.concatMapStringsSep " || " (d: "Host(`${d}`)") allDomains;

  traefikStaticConfig = pkgs.writeText "traefik.yaml" ''
    log:
      level: INFO

    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
      websecure:
        address: ":443"

    certificatesResolvers:
      cloudflare:
        acme:
          email: ${config.mainUser.email}
          storage: /data/acme.json
          dnsChallenge:
            provider: cloudflare
            resolvers:
              - "1.1.1.1:53"

    providers:
      file:
        filename: /etc/traefik/dynamic.yaml
  '';

  traefikDynamicConfig = pkgs.writeText "dynamic.yaml" ''
    http:
      routers:
        browser:
          rule: "${domainRules}"
          entryPoints:
            - websecure
          service: browser
          tls:
            certResolver: cloudflare
      services:
        browser:
          loadBalancer:
            servers:
              - url: "http://127.0.0.1:48945"
  '';

  # Keep Chromium visible through KasmVNC so a person can complete logins and
  # CAPTCHAs. Playwright attaches to its CDP endpoint and therefore uses the
  # same persisted profile without a browser extension.
  runChromium = pkgs.writeShellApplication {
    name = "${containerName}-run";
    text = ''
      /usr/bin/docker rm -f ${containerName} >/dev/null 2>&1 || true
      exec /usr/bin/docker run --rm --name ${containerName} \
        --network host \
        --shm-size=1g \
        -e PUID="$(id -u)" \
        -e PGID="$(id -g)" \
        -e TZ=Europe/Berlin \
        -e CHROME_CLI="--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222" \
        --env-file ${envFile} \
        -v ${dataDir}:/config \
        lscr.io/linuxserver/chromium:latest
    '';
  };

  runTraefik = pkgs.writeShellApplication {
    name = "${proxyContainerName}-run";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      /usr/bin/docker rm -f ${proxyContainerName} >/dev/null 2>&1 || true
      mkdir -p "${proxyDataDir}"
      touch "${proxyDataDir}/acme.json"
      chmod 600 "${proxyDataDir}/acme.json"
      exec /usr/bin/docker run --rm --name ${proxyContainerName} \
        --network host \
        --env-file ${proxyEnvFile} \
        -v ${traefikStaticConfig}:/etc/traefik/traefik.yaml:ro \
        -v ${traefikDynamicConfig}:/etc/traefik/dynamic.yaml:ro \
        -v ${proxyDataDir}:/data \
        traefik:latest
    '';
  };
in
{
  sops = {
    secrets = {
      "browser-mcp/vnc/user".sopsFile = config.host.sopsFile;
      "browser-mcp/vnc/password".sopsFile = config.host.sopsFile;
      "cloudflare/email".sopsFile = config.host.sopsDefaultFile;
      "cloudflare/api_key".sopsFile = config.host.sopsDefaultFile;
    };

    templates = {
      "${containerName}.env".content = ''
        CUSTOM_USER=${config.sops.placeholder."browser-mcp/vnc/user"}
        PASSWORD=${config.sops.placeholder."browser-mcp/vnc/password"}
        CUSTOM_PORT=48945
        CUSTOM_HTTPS_PORT=48946
      '';

      "${proxyContainerName}.env".content = ''
        CF_API_EMAIL=${config.sops.placeholder."cloudflare/email"}
        CF_API_KEY=${config.sops.placeholder."cloudflare/api_key"}
        CLOUDFLARE_EMAIL=${config.sops.placeholder."cloudflare/email"}
        CLOUDFLARE_API_KEY=${config.sops.placeholder."cloudflare/api_key"}
      '';
    };
  };

  home.activation.createBrowserMcpChromiumDataDir = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    run mkdir -p "${dataDir}"
    run mkdir -p "${proxyDataDir}"
  '';

  # docker itself is fnuc's system-provided /usr/bin/docker (fnuc is a
  # standalone, non-NixOS Home Manager host), not a Nix-managed daemon.
  systemd.user.services.${containerName} = {
    Unit = {
      Description = "Interactive Chromium with Playwright CDP access";
      After = [ "docker.service" ];
    };
    Service = {
      ExecStart = "${runChromium}/bin/${containerName}-run";
      ExecStop = "/usr/bin/docker stop ${containerName}";
      Restart = "always";
      RestartSec = "10s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.${proxyContainerName} = {
    Unit = {
      Description = "Traefik reverse proxy for browser MCP KasmVNC";
      After = [
        "docker.service"
        "${containerName}.service"
      ];
      Wants = [ "${containerName}.service" ];
    };
    Service = {
      ExecStart = "${runTraefik}/bin/${proxyContainerName}-run";
      ExecStop = "/usr/bin/docker stop ${proxyContainerName}";
      Restart = "always";
      RestartSec = "10s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # The remote debugging port listens only on the host loopback interface.
  # rofl-13/rofl-14 are reached over SSH so their CDP ports remain private too.
  programs.mcp.servers = {
    playwright-fnuc = {
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [ "--cdp-endpoint=http://127.0.0.1:9222" ];
    };

    playwright-rofl-13 = {
      command = "ssh";
      args = [
        "-o"
        "BatchMode=yes"
        "rofl-13"
        "${pkgs.playwright-mcp}/bin/playwright-mcp"
        "--cdp-endpoint=http://127.0.0.1:9222"
      ];
    };

    playwright-rofl-14 = {
      command = "ssh";
      args = [
        "-o"
        "BatchMode=yes"
        "rofl-14"
        "${pkgs.playwright-mcp}/bin/playwright-mcp"
        "--cdp-endpoint=http://127.0.0.1:9222"
      ];
    };
  };
}
