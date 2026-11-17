{ config, lib, ... }:
{
  options.termux.motd.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to display TermuxPP and SSH welcome text.";
  };

  config = lib.mkIf (!config.termux.motd.enable) {
    termux.homeFiles = lib.mkOptionDefault (
      lib.mkAfter [
        ".config/termuxpp/motd.sh"
        ".config/termux-native/sshd-motd.conf"
      ]
    );

    xdg.configFile = {
      "termuxpp/motd.sh" = {
        executable = true;
        text = ''
          #!/system/bin/sh
          # TermuxPP welcome text is disabled for this profile.
        '';
      };
      "termux-native/sshd-motd.conf".text = "PrintMotd no\n";
    };
  };
}
