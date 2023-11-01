{ pkgs, inputs, config, ... }:

let username = "p.schmitt_admin";

in
{

  age = {
    secrets = {
      gec-ca.file = "/etc/nixos/secrets/gec-vpn/gec-ca.pem.age";
      gec-cert.file = "/etc/nixos/secrets/gec-vpn/gec-cert.pem.age";
      gec-key.file = "/etc/nixos/secrets/gec-vpn/gec-key.pem.age";
    };
    identityPaths = [ "${config.custom.homeDirectory}/.ssh/id_ed25519" ];
  };

  environment.systemPackages = with pkgs; [
    openconnect
    openvpn
  ];

  environment.etc =
    let
      conn_openconnect = (pkgs.formats.ini { }).generate "gec-vpn-openconnect.nmconnection" {
        connection = {
          id = "GEC VPN (OpenConnect)";
          autoconnect = false;
          type = "vpn";
          uuid = "69bdac6c-b8b9-40dd-ab25-093b220a3205";
        };

        vpn = {
          autoconnect-flags = "0";
          certsigs-flags = "0";
          cookie-flags = "2";
          enable_csd_trojan = "no";
          gateway = "mgmt-vpn.gec.io";
          gateway-flags = "2";
          gwcert-flags = "2";
          lasthost-flags = "0";
          pem_passphrase_fsid = "no";
          prevent_invalid_cert = "no";
          protocol = "anyconnect";
          resolve-flags = "2";
          stoken_source = "disabled";
          xmlconfig-flags = "0";
          service-type = "org.freedesktop.NetworkManager.openconnect";
        };

        vpn-secrets = {
          # NOTE: The username must be lowercase, or wrong routes get pushed!
          "form:main:username" = username;
          lasthost = "mgmt-vpn.gec.io";
        };

        ipv4 = {
          method = "auto";
          never-default = true;
        };

        ipv6 = {
          addr-gen-mode = "stable-privacy";
          method = "auto";
        };
      };

      conn_openvpn = (pkgs.formats.ini { }).generate "gec-vpn-openvpn.nmconnection" {
        connection = {
          id = "GEC VPN (OpenVPN)";
          type = "vpn";
          uuid = "708a8205-399a-47df-9cac-7e31092f4f17";
        };

        vpn = {
          service-type = "org.freedesktop.NetworkManager.openvpn";

          ca = "/etc/NetworkManager/certs/gec-ca.pem";
          cert = "/etc/NetworkManager/certs/gec-cert.pem";
          key = "/etc/NetworkManager/certs/gec-key.pem";
          username = username;
          password-flags = 1;
          connection-type = "password-tls";
          remote = "mgmt-vpn.gec.io:1194:udp, mgmt-vpn.gec.io:443:tcp";
          cipher = "AES-256-GCM";
          remote-cert-tls = "server";
          reneg-seconds = 0;
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
      "NetworkManager/system-connections/${conn_openconnect.name}" = {
        source = conn_openconnect;
        mode = "0600";
      };

      "NetworkManager/system-connections/${conn_openvpn.name}" = {
        source = conn_openvpn;
        mode = "0600";
      };

      "NetworkManager/certs/gec-ca.pem" = {
        source = config.age.secrets.gec-ca.path;
        mode = "0600";
      };

      "NetworkManager/certs/gec-cert.pem" = {
        source = config.age.secrets.gec-cert.path;
        mode = "0600";
      };

      "NetworkManager/certs/gec-key.pem" = {
        source = config.age.secrets.gec-key.path;
        mode = "0600";
      };
    };
}
