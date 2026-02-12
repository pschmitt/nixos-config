{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  wiitOvpnConfig = pkgs.fetchurl {
    url = "https://vpn.wiit.one/wiit.ovpn";
    sha256 = "sha256-HsUD8scOdJZSbT1GUTMftrrEodQo34VcqqC78WaAl50=";
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
  wiitFilteredLines = removeUnwantedLines wiitOvpnConfig;

  wiitAuthUserPass = "/run/secrets/openvpn-wiit";

  # Append custom config options
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

  # WIIT
  wiitUsername = "philipp.schmitt";
in
{
  imports = [ inputs.update-systemd-resolved.nixosModules.update-systemd-resolved ];

  environment.systemPackages = with pkgs; [ openvpn ];

  services.openvpn.servers = {
    wiit = {
      config = wiitOvpnConfigMod;
      autoStart = false;
      updateResolvConf = false;
    };
  };

  sops.secrets = {
    "openvpn/wiit/password" = { };
    "openvpn/wiit/totp" = { };
  };

  systemd.services.openvpn-wiit = {
    path = with pkgs; [
      oath-toolkit
      shadow.su
    ];

    preStart = ''
      echo "PreStart: recreate auth file"
      rm -vf "${wiitAuthUserPass}"

      PASSWORD_PREFIX=$(cat ${config.sops.secrets."openvpn/wiit/password".path})
      TOTP=$(oathtool --base32 --totp --digits=6 \
        @${config.sops.secrets."openvpn/wiit/totp".path})
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
    wiit = {
      includeAutomatically = true;
      settings.defaultRoute = false;
    };
  };

  # XXX Once connected to the VPN inno-cloud.de is not resolving correctly
  # dig git.mgmt.innovo-cloud.de @1.1.1.1 A +short
  # networking.extraHosts = "185.32.80.217 git.mgmt.innovo-cloud.de";
}
