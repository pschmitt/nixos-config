{ pkgs, ... }:
{
  # console.useXkbConfig = true;

  # HHKB raw HID for the logged-in user: VIA/Vial in the browser, the ECK and
  # dmk tools and happy-hacking-gnu. Matches the HID device over USB (0003)
  # and Bluetooth (0005): PFU stock firmware (04FE), ECK (CAFE:4012) and dmk
  # (CAFE:4014). uaccess must be set before 73-seat-late.rules, so this is a
  # 70-* rules file instead of services.udev.extraRules (99-local.rules).
  services = {
    udev.packages = [
      (pkgs.writeTextFile {
        name = "hhkb-hidraw-udev-rules";
        destination = "/etc/udev/rules.d/70-hhkb-hidraw.rules";
        text = ''
          SUBSYSTEM=="hidraw", KERNELS=="0003:04FE:*|0005:04FE:*", TAG+="uaccess"
          SUBSYSTEM=="hidraw", KERNELS=="0003:CAFE:4012.*|0005:CAFE:4012.*", TAG+="uaccess"
          SUBSYSTEM=="hidraw", KERNELS=="0003:CAFE:4014.*|0005:CAFE:4014.*", TAG+="uaccess"
        '';
      })
    ];

    xserver.enable = true;
    xserver.xkb =
      let
        symbolsFile = name: "${pkgs.custom-keymaps}/share/X11/xkb/symbols/${name}";
      in
      {
        layout = "de";
        variant = "";

        extraLayouts = {
          hhkb-de = {
            description = "Custom HHKB DE layout by pschmitt";
            languages = [ "deu" ];
            symbolsFile = symbolsFile "hhkb-de";
          };
          gpdpocket4-us = {
            description = "GPD Pocket 4 layout with swapped Y/Z and AltGr tweaks";
            languages = [
              "eng"
              "deu"
            ];
            symbolsFile = symbolsFile "gpdpocket4-us";
          };
          gpdpocket4-de = {
            description = "GPD Pocket 4 custom DE Layout";
            languages = [ "deu" ];
            symbolsFile = symbolsFile "gpdpocket4-de";
          };
        };
      };
  };
}
