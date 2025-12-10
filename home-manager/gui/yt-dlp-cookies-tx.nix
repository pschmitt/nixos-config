{ osConfig, pkgs, ... }:
let
  serviceName = "yt-dlp-cookies-tx";
  installForPinchflat = ''
    ${pkgs.openssh}/bin/ssh "$TARGET_HOST" \
      sudo install --verbose -D \
        --mode=600 \
        --owner=pinchflat \
        --group=pinchflat \
        "$DEST" \
        /var/lib/pinchflat/extras/cookies.txt
  '';
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
          "DEST=/srv/podsync/data/yt-dlp/cookies.txt"
          "SRC_BROWSER=firefox"
          "TARGET_HOST=rofl-10.${osConfig.domains.main}"
        ];

        ExecStart = pkgs.writeShellScript "${serviceName}.sh" ''
          set -x

          TMP_COOKIES=$(mktemp --dry-run --suffix=.txt)
          trap 'rm -f $TMP_COOKIES' EXIT

          # NOTE yt-dlp will complain about a missing url, but the cookies will still be exported
          ${pkgs.yt-dlp}/bin/yt-dlp \
            --cookies-from-browser "$SRC_BROWSER" \
            --cookies "$TMP_COOKIES" || true

          ${pkgs.openssh}/bin/scp "$TMP_COOKIES" "''${TARGET_HOST}:''${DEST}"
          ${installForPinchflat}
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
