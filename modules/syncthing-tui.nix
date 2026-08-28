{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  cfg = config.custom.syncthingTui;

  writeStuiConfig = pkgs.writeShellScript "write-stui-config-${cfg.user}" ''
    set -euo pipefail
    if [ ! -f "${cfg.configXml}" ]; then
      # First-ever run: syncthing hasn't started and written config.xml yet.
      # Nothing to do until the next activation.
      exit 0
    fi
    api_key=$(${pkgs.gnused}/bin/sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "${cfg.configXml}")
    install -d -o ${cfg.user} -g ${cfg.group} -m 0700 "${cfg.homeDirectory}/.config/stui"
    config_file="${cfg.homeDirectory}/.config/stui/config.yaml"
    cat > "$config_file" <<EOF
    api_key: "$api_key"
    base_url: "http://${cfg.guiAddress}"
    icon_mode: "nerdfont"
    open_command: "xdg-open"
    clipboard_command: "wl-copy"
    EOF
    chown ${cfg.user}:${cfg.group} "$config_file"
    chmod 0600 "$config_file"
  '';
in
{
  options.custom.syncthingTui = {
    enable = mkEnableOption "generating stui's config.yaml from a NixOS-managed Syncthing instance";

    user = mkOption {
      type = types.str;
      description = "User to own the generated stui config, and whose Syncthing instance to read.";
    };

    group = mkOption {
      type = types.str;
      default = cfg.user;
      description = "Group to own the generated stui config.";
    };

    homeDirectory = mkOption {
      type = types.path;
      description = "Home directory of `user`, where ~/.config/stui/config.yaml is written.";
    };

    configXml = mkOption {
      type = types.path;
      description = "Path to the Syncthing instance's config.xml to read the GUI API key from.";
    };

    guiAddress = mkOption {
      type = types.str;
      default = "127.0.0.1:8384";
      description = "Syncthing GUI/REST address, written into stui's base_url.";
    };
  };

  config = mkIf cfg.enable {
    # syncthingtui needs no config of its own: it auto-discovers the GUI
    # address and API key straight from config.xml.
    #
    # stui has no such auto-discovery and wants a static config.yaml with
    # the API key already in it. Syncthing generates that key itself on
    # first run rather than it being something set declaratively here
    # (that would put the key in the Nix store/repo); instead, every
    # activation re-reads whatever key is currently in config.xml and
    # regenerates stui's config.yaml to match, so it can't drift or need a
    # manual step.
    system.activationScripts.syncthingTuiConfig = {
      text = "${writeStuiConfig}";
      deps = [ "users" ];
    };
  };
}
