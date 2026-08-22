# Lets Claude Code paste clipboard images over SSH: this ships a `wl-paste`
# binary that shadows the real (non-functional, no Wayland session here) one,
# and forwards the call to whichever client machine's clipboard is reachable
# through this SSH session's reverse tunnel (see
# home-manager/gui/hyprland/services/ssh-clipboard-bridge.nix on the client
# side). The tunnel's socket path is passed in via $CCIMG_SOCK, forwarded
# from the client's ssh_config over SSH's AcceptEnv (sshd_config on fnuc must
# allow it).
{ pkgs, ... }:
let
  wlPasteShim = pkgs.writeShellApplication {
    name = "wl-paste";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.socat
    ];
    text = ''
      sock="''${CCIMG_SOCK:?wl-paste: CCIMG_SOCK is not set - reconnect through the ccimg SSH tunnel}"

      if [[ ! -S "$sock" ]]; then
        echo "wl-paste: $sock: no such socket (client-side ccimgd not reachable)" >&2
        exit 1
      fi

      resp=$(mktemp)
      trap 'rm -f "$resp"' EXIT

      {
        for a in "$@"; do
          printf '%s\n' "$a"
        done
        printf '\n'
      } | socat -T 10 - "UNIX-CONNECT:$sock" > "$resp"

      IFS= read -r statusline < "$resp"
      rc=''${statusline#STATUS }
      skip=$(( ''${#statusline} + 2 ))
      tail -c "+''${skip}" "$resp"
      exit "''${rc:-1}"
    '';
  };
in
{
  home.packages = [ wlPasteShim ];
}
