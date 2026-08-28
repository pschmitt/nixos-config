{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.syncthing;

  # Matches home-manager's own (unexposed) syncthing config location --
  # see nix-community/home-manager modules/services/syncthing.nix.
  configXml = "${config.xdg.stateHome}/syncthing/config.xml";

  # syncthingtui needs no config of its own: it auto-discovers the GUI
  # address and API key straight from config.xml.
  #
  # stui has no such auto-discovery and wants a static config.yaml with the
  # API key already in it. Syncthing generates that key itself on first run
  # rather than it being something this module sets declaratively (doing so
  # would put the key in the Nix store/repo); instead, every activation
  # re-reads whatever key is currently in config.xml and regenerates stui's
  # config.yaml to match, so it can't drift or need a manual step.
  writeStuiConfig = pkgs.writeShellScript "write-stui-config" ''
    set -euo pipefail
    if [ ! -f "${configXml}" ]; then
      # First-ever run: syncthing hasn't started and written config.xml yet.
      # Nothing to do until the next activation.
      exit 0
    fi
    api_key=$(${pkgs.gnused}/bin/sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "${configXml}")
    mkdir -p "${config.xdg.configHome}/stui"
    cat > "${config.xdg.configHome}/stui/config.yaml" <<EOF
    api_key: "$api_key"
    base_url: "http://${cfg.guiAddress}"
    icon_mode: "nerdfont"
    open_command: "xdg-open"
    clipboard_command: "wl-copy"
    EOF
  '';
in
{
  config = lib.mkIf cfg.enable {
    home.activation.syncthingTuiConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${writeStuiConfig}
    '';
  };
}
