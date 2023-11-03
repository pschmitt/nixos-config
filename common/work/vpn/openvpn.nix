{ pkgs, inputs, config, ... }:

let
  ovpnConfig = pkgs.fetchurl {
    url = "https://mgmt-vpn.gec.io/gec.ovpn";
    sha256 = "sha256-PIWDHcoc5fv0vYRaBpJXXUV31wxua1nm5u6pWw3Kp3g=";
  };

  extractOvpnDetails = pkgs.stdenv.mkDerivation {
    name = "extract-ovpn-details";
    src = ovpnConfig;
    phases = ["installPhase"];
    installPhase = ''
      mkdir -p $out/certs $out/details

      awk 'BEGIN {ORS=", "} /remote /{ print $2 ":" $3 ":" $4 }' $src | \
        sed 's#, $##' > "$out/details/remote"

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

  cipher = builtins.readFile "${extractOvpnDetails}/details/cipher";
  remote = builtins.readFile "${extractOvpnDetails}/details/remote";
  remoteCertTls = builtins.readFile "${extractOvpnDetails}/details/remote-cert-tls";
  renegSeconds = builtins.readFile "${extractOvpnDetails}/details/reneg-sec";
  username = "p.schmitt_admin";

in {
  environment.systemPackages = with pkgs; [
    openvpn
  ];

  environment.etc =
    let
      conn_openvpn = (pkgs.formats.ini { }).generate "gec-vpn-openvpn.nmconnection" {
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

          cipher = cipher;
          remote = remote;
          remote-cert-tls = remoteCertTls;
          reneg-seconds = renegSeconds;
          username = username;

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
      "NetworkManager/system-connections/${conn_openvpn.name}" = {
        source = conn_openvpn;
        mode = "0600";
      };

      "NetworkManager/certs/gec-ca.pem" = {
        source = "${extractOvpnDetails}/certs/ca.pem";
        mode = "0600";
      };

      "NetworkManager/certs/gec-cert.pem" = {
        source = "${extractOvpnDetails}/certs/cert.pem";
        mode = "0600";
      };

      "NetworkManager/certs/gec-key.pem" = {
        source = "${extractOvpnDetails}/certs/key.pem";
        mode = "0600";
      };
    };
}

