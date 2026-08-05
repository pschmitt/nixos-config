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

  # fnuc is headless, so the Browser MCP Chrome extension (browsermcp.io) needs
  # a real, visible desktop browser to drive. lscr.io/linuxserver/chromium
  # bundles one behind KasmVNC (web UI on :48945/:48946), so it's both
  # MCP-drivable and manually reachable when the extension needs a human.
  #
  # --network host is required: the extension always dials the MCP server's
  # websocket at ws://localhost:9009, and Docker's default bridge network
  # doesn't map container "localhost" to the host's.
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
      Description = "Real desktop Chromium (linuxserver/chromium, KasmVNC) for Browser MCP";
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

  # Same setup also runs on rofl-13/rofl-14 (services/browser-mcp-chromium-container.nix)
  # for more headroom than fnuc's capped nix-daemon cgroup allows, at the cost of
  # those hosts being cattle/throwaway (no backups of the browser profile). The
  # MCP server has to run on whichever host owns the container (extension only
  # ever dials ws://localhost:9009), so the remote ones are reached by piping
  # stdio over ssh rather than by exposing the port over the network.
  programs.mcp.servers = {
    browsermcp-fnuc = {
      command = "${pkgs.browsermcp}/bin/mcp-server-browsermcp";
    };

    browsermcp-rofl-13 = {
      command = "ssh";
      args = [
        "-o"
        "BatchMode=yes"
        "rofl-13"
        "mcp-server-browsermcp"
      ];
    };

    browsermcp-rofl-14 = {
      command = "ssh";
      args = [
        "-o"
        "BatchMode=yes"
        "rofl-14"
        "mcp-server-browsermcp"
      ];
    };
  };
}
