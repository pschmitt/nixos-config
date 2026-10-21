{ config, ... }:
{
  boot = {
    extraModulePackages = [
      (config.boot.kernelPackages.v4l2loopback.overrideAttrs (old: {
        # modules_install otherwise runs depmod and creates modules.alias etc.,
        # which collide with the kernel's metadata. NixOS runs depmod after
        # combining the kernel and external modules.
        makeFlags = (old.makeFlags or [ ]) ++ [ "DEPMOD=true" ];
        installFlags = (old.installFlags or [ ]) ++ [ "DEPMOD=true" ];
      }))
    ];
    kernelModules = [ "v4l2loopback" ];
    extraModprobeConfig = ''
      # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
      # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
      # https://github.com/umlaeute/v4l2loopback
      options v4l2loopback video_nr=10 exclusive_caps=1 card_label="OBS Virtual Camera"
    '';
  };
}
