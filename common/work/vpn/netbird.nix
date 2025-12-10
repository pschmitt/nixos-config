{
  config,
  lib,
  pkgs,
  ...
}:
let
  netbirdForceRoutes = pkgs.writeShellScriptBin "netbird-force-routes" ''
    set -x

    PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          coreutils # sort
          findutils # xargs
          gawk
          iproute2
          jq
        ]
      )
    }:$PATH"

    NB_INSTANCE_NAME="''${NB_INSTANCE_NAME:-wiit}"
    NB_INTERFACE_NAME="''${NB_INTERFACE_NAME:-nb-$NB_INSTANCE_NAME}"
    NB_BIN="/run/current-system/sw/bin/netbird-$NB_INSTANCE_NAME"

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
        $NB_BIN routes list
        ROUTES=$($NB_BIN routes list | \
          awk '/Network: 10\./ { print $2 }' | \
          sort -u)

        echo "Adding routes over $NB_INTERFACE_NAME for:"
        echo "''${ROUTES:-N/A}"

        <<< "$ROUTES" xargs --verbose -I {} \
            ip route add '{}' dev "$NB_INTERFACE_NAME"
        ;;
      delete)
        ip -j route show | \
          jq -er --arg nb "$NB_INTERFACE_NAME" '
            .[] | select(.dev == $nb and (.dst | test("^10\\."))) | .dst
          ' | xargs --verbose -I {} \
            ip route delete '{}' dev "$NB_INTERFACE_NAME"
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
        dns-resolver = {
          address = "127.0.0.21";
          port = 53;
        };
      };
      wiit-test = {
        port = 51822;
        environment = {
          NB_MANAGEMENT_URL = "https://nb-test.gec.io";
          NB_ALLOW_SSH = "false";
        };
        dns-resolver = {
          address = "127.0.0.22";
          port = 53;
        };
      };
    };
  };

  # Add ourselves to the netbird-wiit groups
  users.users."${config.mainUser.username}".extraGroups = [
    "netbird-wiit"
    "netbird-wiit-test"
  ];

  # FIXME This does not seem to get triggered when the service starts
  systemd.services.netbird-wiit = {
    postStart = ''
      NB_INSTANCE_NAME=wiit

      nb_has_routes() {
        local routes
        if ! routes=$(/run/current-system/sw/bin/netbird-$NB_INSTANCE_NAME routes list)
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

      echo "Running: NB_INSTANCE_NAME=$NB_INSTANCE_NAME ${netbirdForceRoutes}/bin/netbird-force-routes"

      NB_INSTANCE_NAME=$NB_INSTANCE_NAME ${netbirdForceRoutes}/bin/netbird-force-routes
    '';

    preStop = ''
      echo "Deleting netbird routes from main routing table"
      NB_INSTANCE_NAME=wiit \
        ${netbirdForceRoutes}/bin/netbird-force-routes --delete
    '';
  };

  environment.systemPackages = [ netbirdForceRoutes ];
}
