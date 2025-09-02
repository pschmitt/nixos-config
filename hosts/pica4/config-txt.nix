{ pkgs, ... }:
let
  configTxt = ./config.txt;
in
{
  systemd.services.install-config-txt = {
    description = "Install /boot/firmware/config.txt from nix-config repo";
    documentation = [ "https://github.com/pschmitt/nixos-config/blob/HEAD/hosts/pica4/config.txt" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ configTxt ];

    requires = [ "boot-firmware.mount" ];
    after = [ "boot-firmware.mount" ];

    unitConfig = {
      RequiresMountsFor = "/boot/firmware";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils ];
    script = ''
      install --debug --compare \
        --owner=root \
        --mode=0644 \
        "${configTxt}" /boot/firmware/config.txt
      sync
    '';
  };
}
