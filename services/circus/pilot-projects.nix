# Public repositories migrated from nixbot.
let
  project = repository: branch: expression: {
    name = builtins.replaceStrings [ "." ] [ "-" ] repository;
    repository_url = "https://github.com/pschmitt/${repository}";
    jobsets = [
      {
        name = branch;
        inherit branch;
        nix_expression = expression;
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ]
    ++
      builtins.map
        (system: {
          name = "${branch}-arm";
          inherit branch;
          nix_expression = "hydraJobs.${system}";
          systems = [ system ];
          only_build_latest = true;
        })
        (
          if
            builtins.elem repository [
              "anika-blue"
              "browser-daemon"
              "monarch"
              "rbw"
              "rworker"
            ]
          then
            [ "aarch64-linux" ]
          else
            [ ]
        );
  };
in
map (repo: project repo "main" "packages.x86_64-linux") [
  "bunq-sh"
  "codex-ha-bridge"
  "docker-compose-bulk"
  "homeassistant-hrworks"
  "jcalapi"
  "ldifj"
  "luks-mount.sh"
  "myl"
  "myl-discovery"
  "nbx"
  "obs-cli"
  "poor-tools"
  "printlabel"
  "pschmitt.dev"
  "pywax"
  "ruamel-fmt"
  "sendmyl"
  "shelly-ble-rpc"
  "slack-react"
  "tdc"
  "termuxpp"
  "tmux-slay"
  "tsvtool"
  "vodafone-station-cli"
]
++ map (repo: project repo "main" "hydraJobs.x86_64-linux") [
  "anika-blue"
  "browser-daemon"
  "bruvtab"
  "jellysync"
  "luks-ssh-unlock"
  "monarch"
  "noctalia-plugins"
  "rbw"
  "rworker"
  "stricknani"
  "tagesschau"
  "teams-live"
]
++ map (repo: project repo "main" "checks.x86_64-linux") [
  "augh"
  "declaroid"
  "jollyfin"
  "nyetbox"
  "syncwich"
]
++ [
  (project "Gadgetbridge" "master" "devShells.x86_64-linux")
  (project "roombapy" "main" "devShells.x86_64-linux")
]
