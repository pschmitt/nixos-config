_:
let
  target = "graphical-session.target";
in
{
  services.cliphist = {
    enable = true;
    allowImages = true;
    systemdTargets = [ target ];
  };

  services.wl-clip-persist = {
    enable = true;
    clipboardType = "both";
    systemdTargets = [ target ];
  };
}
