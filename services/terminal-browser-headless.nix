# terminal-browser needs kitty (graphics protocol + remote control) to place
# its browser. This runs a headless weston with a kitty inside it so agents on
# a machine without a graphical session can use terminal-browser.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.terminal-browser-headless;

  socketName = "terminal-browser";

  # The browser is launched through kitty, so it inherits kitty's environment.
  # terminal-browser only picks Chromium's headless ozone backend when neither
  # DISPLAY nor WAYLAND_DISPLAY is set, and the software-GL variables below must
  # not leak into Electron, so kitty strips them from its children.
  kittyConfig = pkgs.writeText "terminal-browser-kitty.conf" ''
    allow_remote_control socket-only
    listen_on unix:''${XDG_RUNTIME_DIR}/terminal-browser-kitty.sock
    confirm_os_window_close 0
    shell_integration disabled
    env WAYLAND_DISPLAY
    env DISPLAY
    env LD_LIBRARY_PATH
    env LIBGL_ALWAYS_SOFTWARE
    env GALLIUM_DRIVER
    env __EGL_VENDOR_LIBRARY_FILENAMES
  '';

  wrapper = pkgs.writeShellApplication {
    name = "terminal-browser-headless";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.kitty
      pkgs.llm-agents.terminal-browser
      pkgs.systemd
    ];
    text = builtins.readFile ./scripts/terminal-browser-headless.sh;
  };
in
{
  options.services.terminal-browser-headless.enable = lib.mkEnableOption "terminal-browser in a headless kitty, for agents";

  config = lib.mkIf cfg.enable {
    home.packages = [ wrapper ];

    systemd.user.services = {
      terminal-browser-weston = {
        Unit.Description = "Headless Wayland compositor for terminal-browser";
        Service = {
          ExecStart = lib.concatStringsSep " " [
            (lib.getExe pkgs.weston)
            "--backend=headless"
            "--renderer=pixman"
            "--socket=${socketName}"
            "--width=1920"
            "--height=1080"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      terminal-browser-kitty = {
        Unit = {
          Description = "Headless kitty for terminal-browser";
          After = [ "terminal-browser-weston.service" ];
          BindsTo = [ "terminal-browser-weston.service" ];
        };
        Service = {
          # No GPU on servers: kitty needs OpenGL, so use Mesa's software
          # renderer. llvmpipe crashes (SIGILL) on some VMs, softpipe does not.
          Environment = [
            "WAYLAND_DISPLAY=${socketName}"
            "LIBGL_ALWAYS_SOFTWARE=1"
            "GALLIUM_DRIVER=softpipe"
            "__EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
            "LD_LIBRARY_PATH=${pkgs.mesa}/lib"
          ];
          ExecStartPre = "${pkgs.bash}/bin/bash -c 'for _ in $(seq 50); do [ -S \"$XDG_RUNTIME_DIR/${socketName}\" ] && exit 0; sleep 0.2; done; exit 1'";
          ExecStart = "${lib.getExe pkgs.kitty} --config ${kittyConfig}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  };
}
