{
  pkgs,
  inputs,
  config,
  ...
}:
let
  username = "p.schmitt_admin";
  remote = "mgmt-vpn.gec.io";
in
{

  environment.systemPackages = with pkgs; [ openconnect ];

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
          gateway = remote;
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
          lasthost = remote;
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
      "NetworkManager/system-connections/${conn_openconnect.name}" = {
        source = conn_openconnect;
        mode = "0600";
      };
    };
}
