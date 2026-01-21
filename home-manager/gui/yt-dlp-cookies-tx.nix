{ osConfig, pkgs, ... }:
let
  serviceName = "yt-dlp-cookies-tx";
in
{
  systemd.user = {
    services."${serviceName}" = {
      Unit = {
        Description = "Export yt-dl cookies from Firefox and copy to rofl-10, for pinchflat";
        Documentation = [
          "https://github.com/mxpv/podsync"
          "https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp"
        ];
      };

      Service = {
        Environment = [
          "DEST=/srv/yt-dlp/cookies.txt"
          "SRC_BROWSER=firefox"
          "TARGET_HOST=rofl-10.${osConfig.domains.main}"
          "RESTART_SERVICES=docker-podsync.service pinchflat.service"
        ];

        ExecStart = pkgs.writeShellScript "${serviceName}.sh" ''
          set -eu

          TMP_COOKIES=$(mktemp --suffix=.txt --dry-run)
          trap 'rm -f "$TMP_COOKIES"' EXIT

          # NOTE yt-dlp will complain about a missing url, but the cookies will still be exported
          ${pkgs.yt-dlp}/bin/yt-dlp \
            --cookies-from-browser "$SRC_BROWSER" \
            --cookies "$TMP_COOKIES" || true

          if [ ! -s "$TMP_COOKIES" ]
          then
            echo "No cookies exported; refusing to upload." >&2
            exit 1
          fi

          REMOTE_TMP=$(${pkgs.openssh}/bin/ssh "$TARGET_HOST" mktemp --suffix=.txt)
          if [ -z "$REMOTE_TMP" ]
          then
            echo "Failed to allocate a remote temp file." >&2
            exit 1
          fi

          ${pkgs.openssh}/bin/scp "$TMP_COOKIES" "''${TARGET_HOST}:''${REMOTE_TMP}"
          ${pkgs.openssh}/bin/ssh "$TARGET_HOST" \
            sudo install --verbose -D \
              --mode=640 \
              --owner=pinchflat \
              --group=pinchflat \
              "$REMOTE_TMP" \
              "$DEST"
          ${pkgs.openssh}/bin/ssh "$TARGET_HOST" rm -f "$REMOTE_TMP"
          ${pkgs.openssh}/bin/ssh "$TARGET_HOST" sudo systemctl restart $RESTART_SERVICES
        '';
      };
    };

    timers.${serviceName} = {
      Unit.Description = "Regularly transfer cookies.txt to rofl-10 for pinchflat";

      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "30m";
        Persistent = true;
        AccuracySec = "30m";
      };

      Install.WantedBy = [ "timers.target" ];
    };
  };
}
