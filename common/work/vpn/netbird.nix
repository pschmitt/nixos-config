{
  config,
  pkgs,
  lib,
  ...
}:
let
  netbirdPkg = pkgs.netbird; # or pkgs.master.netbird
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
      # exec /run/wrappers/bin/sudo ${netbirdPkg}/bin/netbird "$@"
      exec ${netbirdPkg}/bin/netbird "$@"
    '';

  netbirdScripts = lib.genAttrs (lib.attrNames config.services.netbird.tunnels) (
    name: createNetbirdScript name config.services.netbird.tunnels.${name}
  );

  netbirdWiitForceRoutes = pkgs.writeShellScriptBin "netbird-wiit-force-routes" ''
    set -x

    # Default action
    ACTION="add"
    NB_INTERFACE_NAME="wiit"

    case "$1" in
      -h|--help)
        echo "Usage: $(basename "$0") [--delete]"
        exit 0
        ;;
      *undo|*remove|*del*|*rm*|*clear*)
        ACTION="delete"
        ;;
    esac

    case "$ACTION" in
      add)
        ${netbirdScripts.wiit}/bin/netbird-wiit routes list
        ROUTES=$(${netbirdScripts.wiit}/bin/netbird-wiit routes list | \
          ${pkgs.gawk}/bin/awk '/Network: 10\./ { print $2 }' | \
          ${pkgs.coreutils}/bin/sort -u)
        echo "Adding routes over $NB_INTERFACE_NAME for:"
        echo "''${ROUTES:-N/A}"

        <<< "$ROUTES" ${pkgs.findutils}/bin/xargs --verbose -I {} \
            ${pkgs.iproute2}/bin/ip route add '{}' dev "$NB_INTERFACE_NAME"
      ;;
      delete)
        ${pkgs.iproute2}/bin/ip -j route show | \
        ${pkgs.jq}/bin/jq -er --arg nb "$NB_INTERFACE_NAME" '
         .[] | select(.dev == $nb and (.dst | test("^10\\."))) | .dst
        ' | \
        ${pkgs.findutils}/bin/xargs --verbose -I {} \
          ${pkgs.iproute2}/bin/ip route delete '{}' dev "$NB_INTERFACE_NAME"
      ;;
    esac
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
  systemd.services.netbird-wiit = {
    postStart = ''
      nb_has_routes() {
        local routes
        if ! routes=$(${netbirdScripts.wiit}/bin/netbird-wiit routes list)
        then
          return 1
        fi

        # {
        #   echo "[DEBUG] netbird routes list:"
        #   echo "$routes"
        # } >&2

        ${pkgs.gnugrep}/bin/grep -vq 'No routes available' <<< "$routes"
      }

      until nb_has_routes
      do
        echo "Waiting for netbird route info to be available"
        sleep 1
      done

      echo "Netbird route info is available"

      echo "Running: ${netbirdWiitForceRoutes}/bin/netbird-wiit-force-routes"
      echo "Adding routes over $NB_INTERFACE_NAME for:"
      echo "''${ROUTES:-N/A}"

      ${netbirdWiitForceRoutes}/bin/netbird-wiit-force-routes
    '';

    preStop = ''
      echo "Deleting netbird routes from main routing table"
      ${netbirdWiitForceRoutes}/bin/netbird-wiit-force-routes --delete
    '';
  };

  environment.systemPackages = lib.attrValues netbirdScripts ++ [ netbirdWiitForceRoutes ];
}
