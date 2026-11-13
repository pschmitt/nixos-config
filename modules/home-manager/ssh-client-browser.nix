{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.ssh-client-browser;
in
{
  options.programs.ssh-client-browser = {
    enable = lib.mkEnableOption ''
      a `$BROWSER` shim that opens URLs in the browser of the machine the
      user is connected from (attached tmux client or SSH session) by running
      its `$BROWSER` over SSH, falling back to a local browser
    '';

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The `ssh-client-browser` shim.";
      default = pkgs.writeShellApplication {
        name = "ssh-client-browser";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.openssh
          pkgs.tmux
        ];
        text = builtins.readFile ./scripts/ssh-client-browser.sh;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
