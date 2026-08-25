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
in
{
  sops.secrets = {
    "browser-mcp/vnc/user".sopsFile = config.host.sopsFile;
    "browser-mcp/vnc/password".sopsFile = config.host.sopsFile;
  };

  sops.templates."${containerName}.env".content = ''
    CUSTOM_USER=${config.sops.placeholder."browser-mcp/vnc/user"}
    PASSWORD=${config.sops.placeholder."browser-mcp/vnc/password"}
    CUSTOM_PORT=48945
    CUSTOM_HTTPS_PORT=48946
  '';

  home.activation.createBrowserMcpChromiumDataDir = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    run mkdir -p "${dataDir}"
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
