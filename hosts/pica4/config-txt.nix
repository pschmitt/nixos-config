{ pkgs, ... }:
let
  configTxt = ./config.txt;
in
{
  systemd.services.config-txt = {
    description = "Install config.txt from nix-config repo";
    documentation = [ "https://github.com/pschmitt/nixos-config/blob/HEAD/hosts/pica4/config.txt" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ configTxt ];
    restartIfChanged = true;

    requires = [ "boot-firmware.mount" ];
    after = [ "boot-firmware.mount" ];
    unitConfig.RequiresMountsFor = "/boot/firmware";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [
      pkgs.coreutils
      pkgs.diffutils
    ];

    script = ''
      DEST=/boot/firmware/config.txt

      if diff --unified --new-file "${configTxt}" "$DEST"
      then
        echo "No changes in config.txt, nothing to do."
        exit 0
      fi

      echo "Installing updated config.txt from '${configTxt}' to '$DEST'"

      install --debug --compare \
        --owner=root \
        --mode=0644 \
        "${configTxt}" "$DEST"

      sync --file-system "$DEST"
    '';
  };
}
