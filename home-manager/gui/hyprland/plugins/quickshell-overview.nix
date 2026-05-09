{ pkgs, ... }:
{
  systemd.user.services.quickshell-overview = {
    Unit = {
      Description = "https://github.com/Shanu-Kumawat/quickshell-overview";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${pkgs.quickshell-overview}/bin/quickshell-overview";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  xdg.configFile."hypr/lua/plugin-quickshell.lua".text = ''
    hl.bind("SUPER + tab", hl.dsp.exec_cmd("${pkgs.quickshell-overview}/bin/quickshell-overview-ipc"))

    hl.config({
        decoration = { dim_around = 0.8 },
        -- layerrule = "dimaround, quickshell:overview"  -- TODO: uncomment when supported
    })
  '';
}
