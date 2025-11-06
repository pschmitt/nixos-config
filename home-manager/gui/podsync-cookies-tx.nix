{ osConfig, pkgs, ... }:
let
  serviceName = "podsync-cookies-tx";
in
{
  systemd.user = {
    services."${serviceName}" = {
      Unit = {
        description = "Export yt-dl cookies from Firefox and copy to rofl-10, for podsync";
        documentation = [
          "https://github.com/mxpv/podsync"
          "https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp"
        ];
      };

      Service = {
        Environment = [
          "DEST=/srv/podsync/data/yt-dlp/cookies.txt"
          "SRC_BROWSER=firefox"
          "TARGET_HOST=rofl-10.${osConfig.custom.mainDomain}"
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
        '';
      };

      Install = {
        wantedBy = [ "default.target" ];
      };
    };

    timers.${serviceName} = {
      Unit = {
        Description = "Regularly transfer cookies.txt to podsync";
      };
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "30m";
        Persistent = true;
        AccuracySec = "30m";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
