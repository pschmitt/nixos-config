{ pkgs, inputs, ... }: {

  environment.systemPackages = with pkgs; [
    openconnect
    openvpn
  ];

  environment.etc =
    let
      conn = (pkgs.formats.ini { }).generate "gec-vpn.nmconnection" {
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
          "form:main:username" = "p.schmitt_admin";
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

    in
    {
      "NetworkManager/system-connections/${conn.name}" = {
        source = conn;
        mode = "0600";
      };
    };
}
