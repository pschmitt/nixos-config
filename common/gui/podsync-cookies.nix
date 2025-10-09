{ config, pkgs, ... }:
let
  serviceName = "podsync-cookies-transfer";
in
{
  systemd.user.services."${serviceName}" = {
    description = "Export yt-dlp cookies from Firefox and copy to rofl-10, for podsync";
    documentation = [
      "https://github.com/mxpv/podsync"
      "https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp"
    ];

    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];

    environment = {
      DEST = "/srv/podsync/data/yt-dlp/cookies.txt";
      SRC_BROWSER = "firefox";
      TARGET_HOST = "rofl-10.${config.custom.mainDomain}";
    };

    script = ''
      set -x
      tmp_cookies=$(mktemp --dry-run --suffix=.txt)
      trap 'rm -f $tmp_cookies' EXIT
      # NOTE yt-dlp will complain about a missing url, but the cookies will still be exported
      ${pkgs.yt-dlp}/bin/yt-dlp --cookies-from-browser "$SRC_BROWSER" --cookies "$tmp_cookies" || true
      ${pkgs.openssh}/bin/scp "$tmp_cookies" "''${TARGET_HOST}:''${DEST}"
    '';

    wantedBy = [ "default.target" ];
  };

  systemd.user.timers."${serviceName}" = {
    description = "Regularly transfer cookies.txt to rofl-10 for podsync";

    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "12h";
      Persistent = true;
    };

    wantedBy = [ "timers.target" ];
  };
}
