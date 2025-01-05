{ pkgs, ... }:
{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  programs = {
    uwsm = {
      enable = true;
      waylandCompositors = {
        sway = {
          prettyName = "sway";
          comment = "sway compositor managed by UWSM";
          binPath = "${pkgs.sway}/bin/sway";
          # binPath = "/run/current-system/sw/bin/sway";
        };
      };
    };
  };
}
