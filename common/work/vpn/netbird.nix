{
  config,
  pkgs,
  lib,
  ...
}:
let
  createNetbirdScript =
    tunnelName: tunnelConfig:
    pkgs.writeShellScriptBin "netbird-${tunnelName}" ''
      # Set environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: ''export ${name}="${value}"'') tunnelConfig.environment
      )}

      # Run netbird
      # TODO Stupidly prepending sudo to the command doesn't work and just
      # breaks the netbird cli
      # exec /run/wrappers/bin/sudo ${pkgs.netbird}/bin/netbird "$@"
      exec ${pkgs.master.netbird}/bin/netbird "$@"
    '';

  netbirdScripts = lib.genAttrs (lib.attrNames config.services.netbird.tunnels) (
    name: createNetbirdScript name config.services.netbird.tunnels.${name}
  );

  netbirdWiitForceRoutes = pkgs.writeShellScriptBin "netbird-wiit-force-routes" ''
    ACTION="add"

    case "$1" in
      -h|--help)
        echo "Usage: $(basename "$0") [--delete]"
        exit 0
        ;;
      *undo|*remove|*del*|*rm*|*clear*)
        ACTION="delete"
        ;;
    esac

    NB_INTERFACE_NAME="wiit"

    ${netbirdScripts.wiit}/bin/netbird-wiit routes list | \
      ${pkgs.gawk}/bin/awk '/Network: 10\./ { print $2 }' | \
      ${pkgs.coreutils}/bin/sort -u | \
      ${pkgs.findutils}/bin/xargs --verbose -I {} \
        ${pkgs.iproute2}/bin/ip route "$ACTION" {} dev "$NB_INTERFACE_NAME"
  '';
in
{
  services.netbird = {
    enable = true;
    tunnels = {
      wiit = {
        port = 51821;
        environment = {
          NB_MANAGEMENT_URL = "https://nb.gec.io";
          NB_ALLOW_SSH = "false";
        };
      };
    };
  };

  # FIXME This does not seem to get triggered when the service starts
  systemd.services.netbird-wiit.postStart = "${netbirdWiitForceRoutes}/bin/netbird-wiit-force-routes";

  environment.systemPackages = lib.attrValues netbirdScripts ++ [ netbirdWiitForceRoutes ];
}
