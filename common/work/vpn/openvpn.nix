{
  config,
  lib,
  pkgs,
  ...
}:

let
  gecOvpnConfig = pkgs.fetchurl {
    url = "https://mgmt-vpn.gec.io/gec.ovpn";
    sha256 = "sha256-PIWDHcoc5fv0vYRaBpJXXUV31wxua1nm5u6pWw3Kp3g=";
  };

  wiitOvpnConfig = pkgs.fetchurl {
    url = "https://vpn.wiit.one/wiit.ovpn";
    sha256 = "sha256-FaR5/ziamaoAyOWWsgb60sd279547GxoI44u+TOHjFI=";
  };

  # Remove "auth-user-pass"
  removeUnwantedLines =
    configPath:
    let
      configContent = builtins.readFile configPath;
      lines = lib.splitString "\n" configContent;
      # Regular expression to match either "auth-user-pass" or "dev tun"
      unwantedRegex = "auth-user-pass|dev tun";
    in
    lib.filter (line: builtins.match unwantedRegex line == null) lines;

  # Apply the function to your configuration files
  gecFilteredLines = removeUnwantedLines gecOvpnConfig;
  wiitFilteredLines = removeUnwantedLines wiitOvpnConfig;

  gecAuthUserPass = "/run/secrets/openvpn-gec";
  wiitAuthUserPass = "/run/secrets/openvpn-wiit";

  # Append custom config options
  gecOvpnConfigMod = lib.concatStringsSep "\n" (
    gecFilteredLines
    ++ [
      "dev ovpn-gec"
      "dev-type tun"
      "auth-user-pass ${gecAuthUserPass}"
      # "auth-nocache"
    ]
  );
  wiitOvpnConfigMod = lib.concatStringsSep "\n" (
    wiitFilteredLines
    ++ [
      "dev ovpn-wiit"
      "dev-type tun"
      "auth-user-pass ${wiitAuthUserPass}"
      # "auth-nocache"
      "setenv UV_IP4_TABLE FRA"
    ]
  );

  extractOvpnDetails =
    { name, src }:
    pkgs.stdenv.mkDerivation {
      inherit name;
      inherit src;
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/certs $out/details

        # Use all remotes
        awk 'BEGIN {ORS=", "} /remote /{ print $2 ":" $3 ":" $4 }' $src | \
         sed 's#, $##' > "$out/details/remote"

        # NOTE Below supports multiple remotes, but our network guys just can't be
        # arsed to fix the ovpn config file, the udp endpoint leads to a
        # succesful connection - but the traffic is relayed properly
        # https://gec-chat.slack.com/archives/C3PBP7JQ3/p1705064366061199
        # Grab the first TCP endpoint and call it a day
        # awk '/^remote / && !/udp/ { print $2 ":" $3 ":" $4; exit }' $src | \
        #   sed 's#, $##' > "$out/details/remote"

        awk '/^cipher / { print $2 }' $src \
          > "$out/details/cipher"
        awk '/^remote-cert-tls / { print $2 }' $src \
          > "$out/details/remote-cert-tls"
        awk '/^reneg-sec / { print $2 }' $src \
          > "$out/details/reneg-sec"

        awk '/<ca>/{flag=1; next} /<\/ca>/{flag=0} flag {print $0}' $src \
          > "$out/certs/ca.pem"
        awk '/<cert>/{flag=1; next} /<\/cert>/{flag=0} flag {print $0}' $src \
          > "$out/certs/cert.pem"
        awk '/<key>/{flag=1; next} /<\/key>/{flag=0} flag {print $0}' $src \
          > "$out/certs/key.pem"
      '';
    };

  # GEC
  gecOpenVPNDetails = extractOvpnDetails {
    name = "gec-openvpn-details";
    src = gecOvpnConfig;
  };
  gecCipher = builtins.readFile "${gecOpenVPNDetails}/details/cipher";
  gecRemote = builtins.readFile "${gecOpenVPNDetails}/details/remote";
  gecRemoteCertTls = builtins.readFile "${gecOpenVPNDetails}/details/remote-cert-tls";
  gecRenegSeconds = builtins.readFile "${gecOpenVPNDetails}/details/reneg-sec";

  gecUsername = "p.schmitt_admin";

  # WIIT
  wiitOpenVPNDetails = extractOvpnDetails {
    name = "wiit-openvpn-details";
    src = wiitOvpnConfig;
  };
  wiitCipher = builtins.readFile "${wiitOpenVPNDetails}/details/cipher";
  wiitRemote = builtins.readFile "${wiitOpenVPNDetails}/details/remote";
  wiitRemoteCertTls = builtins.readFile "${wiitOpenVPNDetails}/details/remote-cert-tls";
  wiitRenegSeconds = builtins.readFile "${wiitOpenVPNDetails}/details/reneg-sec";
  wiitUsername = "philipp.schmitt";
in
{
  environment.systemPackages = with pkgs; [ openvpn ];

  environment.etc =
    let
      gecOpenVPNConnection = (pkgs.formats.ini { }).generate "gec-vpn-openvpn.nmconnection" {
        connection = {
          id = "GEC VPN (OpenVPN)";
          type = "vpn";
          uuid = "808a8205-399a-47df-9cac-7e31092f4f17";
        };

        vpn = {
          service-type = "org.freedesktop.NetworkManager.openvpn";
          ca = "/etc/NetworkManager/certs/gec-ca.pem";
          cert = "/etc/NetworkManager/certs/gec-cert.pem";
          key = "/etc/NetworkManager/certs/gec-key.pem";

          dev = "gec-ovpn";
          dev-type = "tun";

          cipher = gecCipher;
          remote = gecRemote;
          remote-cert-tls = gecRemoteCertTls;
          reneg-seconds = gecRenegSeconds;
          username = gecUsername;

          connection-type = "password-tls";
          password-flags = 1;
        };

        ipv4 = {
          method = "auto";
          never-default = true;
        };

        ipv6 = {
          method = "auto";
          addr-gen-mode = "stable-privacy";
          never-default = true;
        };

        proxy = { };
      };

      wiitOpenVPNConnection = (pkgs.formats.ini { }).generate "wiit-vpn-openvpn.nmconnection" {
        connection = {
          id = "WIIT VPN (OpenVPN)";
          type = "vpn";
          uuid = "808a8205-399a-47df-9cac-7e31092f4f18";
        };

        vpn = {
          service-type = "org.freedesktop.NetworkManager.openvpn";
          ca = "/etc/NetworkManager/certs/wiit-ca.pem";
          cert = "/etc/NetworkManager/certs/wiit-cert.pem";
          key = "/etc/NetworkManager/certs/wiit-key.pem";

          dev = "wiit-ovpn";
          dev-type = "tun";

          cipher = wiitCipher;
          remote = wiitRemote;
          remote-cert-tls = wiitRemoteCertTls;
          reneg-seconds = wiitRenegSeconds;
          username = wiitUsername;

          push-peer-info = "yes";
          # FIXME We need to make NetworkManager set the following OpenVPN
          # option for the VPN to work: "setenv UV_IP4_TABLE FRA"
          # https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/80
          # setenv = "UV_IP4_TABLE=FRA";

          connection-type = "password-tls";
          password-flags = 1;
        };

        ipv4 = {
          method = "auto";
          never-default = true;
        };

        ipv6 = {
          method = "auto";
          addr-gen-mode = "stable-privacy";
          never-default = true;
        };

        proxy = { };
      };
    in
    {
      "NetworkManager/system-connections/${gecOpenVPNConnection.name}" = {
        source = gecOpenVPNConnection;
        mode = "0600";
      };

      "NetworkManager/certs/gec-ca.pem" = {
        source = "${gecOpenVPNDetails}/certs/ca.pem";
        mode = "0600";
      };

      "NetworkManager/certs/gec-cert.pem" = {
        source = "${gecOpenVPNDetails}/certs/cert.pem";
        mode = "0600";
      };

      "NetworkManager/certs/gec-key.pem" = {
        source = "${gecOpenVPNDetails}/certs/key.pem";
        mode = "0600";
      };

      # WIIT
      "NetworkManager/system-connections/${wiitOpenVPNConnection.name}" = {
        source = wiitOpenVPNConnection;
        mode = "0600";
      };

      "NetworkManager/certs/wiit-ca.pem" = {
        source = "${wiitOpenVPNDetails}/certs/ca.pem";
        mode = "0600";
      };

      "NetworkManager/certs/wiit-cert.pem" = {
        source = "${wiitOpenVPNDetails}/certs/cert.pem";
        mode = "0600";
      };

      "NetworkManager/certs/wiit-key.pem" = {
        source = "${wiitOpenVPNDetails}/certs/key.pem";
        mode = "0600";
      };
    };

  services.openvpn.servers = {
    gec = {
      config = gecOvpnConfigMod;
      autoStart = false;
      updateResolvConf = false;
    };
    wiit = {
      config = wiitOvpnConfigMod;
      autoStart = false;
      updateResolvConf = false;
    };
  };

  systemd.services.openvpn-gec = {
    path = with pkgs; [
      zsh
      bitwarden-cli
      jq
      shadow.su
    ];
    preStart = ''
      echo "PreStart: recreate auth file"
      rm -vf "${gecAuthUserPass}"

      PASSWORD="$(su pschmitt -c 'bww -o gec-ovpn')"
      CREDENTIALS="${gecUsername}\n$PASSWORD"

      echo -e "$CREDENTIALS" > "${gecAuthUserPass}"
      chmod 400 "${gecAuthUserPass}"
    '';
    postStart = ''
      echo "PostStart: delete auth file"
      rm -vf "${gecAuthUserPass}"
    '';
    preStop = ''
      echo "PreStop: delete auth file"
      rm -vf "${gecAuthUserPass}"
    '';
  };

  sops.secrets = {
    "openvpn/wiit/password" = { };
    "openvpn/wiit/totp" = { };
  };

  systemd.services.openvpn-wiit = {
    path = with pkgs; [
      zsh
      bitwarden-cli
      jq
      shadow.su
    ];
    preStart = ''
      echo "Prestart: recreate auth file"
      rm -vf "${wiitAuthUserPass}"

      PASSWORD_PREFIX=$(cat ${config.sops.secrets."openvpn/wiit/password".path})
      TOTP_SECRET=$(cat ${config.sops.secrets."openvpn/wiit/totp".path})
      TOTP=$(${pkgs.oath-toolkit}/bin/oathtool --base32 --totp --digits=6 "$TOTP_SECRET")
      PASSWORD="''${PASSWORD_PREFIX}''${TOTP}"
      CREDENTIALS="${wiitUsername}\n$PASSWORD"

      echo -e "$CREDENTIALS" > "${wiitAuthUserPass}"
      chmod 400 "${wiitAuthUserPass}"
    '';
    postStart = ''
      echo "PostStart: delete auth file"
      rm -vf "${wiitAuthUserPass}"
    '';
    preStop = ''
      echo "PreStop: delete auth file"
      rm -vf "${wiitAuthUserPass}"
    '';
  };

  programs.update-systemd-resolved.servers = {
    gec = {
      includeAutomatically = true;
      settings.defaultRoute = false;
    };
    wiit = {
      includeAutomatically = true;
      settings.defaultRoute = false;
    };
  };
}
