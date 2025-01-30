{
  config,
  pkgs,
  ...
}:
let
  netbirdForceRoutes = pkgs.writeShellScriptBin "netbird-force-routes" ''
    set -x

    NB_INSTANCE_NAME="''${NB_INSTANCE_NAME:-wiit}"
    NB_INTERFACE_NAME="''${NB_INTERFACE_NAME:-nb-$NB_INSTANCE_NAME}"

    # Default action
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

    case "$ACTION" in
      add)
        /run/current-system/sw/bin/netbird-$NB_INSTANCE_NAME routes list
        ROUTES=$(/run/current-system/sw/bin/netbird-$NB_INSTANCE_NAME routes list | \
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
    clients = {
      wiit = {
        port = 51821;
        environment = {
          NB_MANAGEMENT_URL = "https://nb.gec.io";
          NB_ALLOW_SSH = "false";
        };
      };
      wiit-test = {
        port = 51822;
        environment = {
          NB_MANAGEMENT_URL = "https://nb-test.gec.io";
          NB_ALLOW_SSH = "false";
        };
      };
    };
  };

  # Add ourselves to the netbird-wiit groups
  users.users."${config.custom.username}".extraGroups = [
    "netbird-wiit"
    "netbird-wiit-test"
  ];

  # FIXME This does not seem to get triggered when the service starts
  systemd.services.netbird-wiit = {
    postStart = ''
      NB_INSTANCE=wiit
      NB_INTERFACE_NAME="nb-$NB_INSTANCE"

      nb_has_routes() {
        local routes
        if ! routes=$(/run/current-system/sw/bin/netbird-$NB_INSTANCE routes list)
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

      echo "Running: NB_INTERFACE_NAME=$NB_INTERFACE_NAME ${netbirdForceRoutes}/bin/netbird-force-routes"

      ${netbirdForceRoutes}/bin/netbird-force-routes
    '';

    preStop = ''
      echo "Deleting netbird routes from main routing table"
      NB_INTERFACE_NAME=$NB_INTERFACE_NAME \
        ${netbirdForceRoutes}/bin/netbird-force-routes --delete
    '';
  };

  environment.systemPackages = [ netbirdForceRoutes ];
}
