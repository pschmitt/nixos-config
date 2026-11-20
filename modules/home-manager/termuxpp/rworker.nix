{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fullNix.rworker;

  rworker = pkgs.rworker.override {
    extraRuntimeInputs = [ pkgs.hostname ];
    sshControlMaster = false;
  };

  rworker-nix = pkgs.writeShellApplication {
    name = "rworker-nix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssh
      rworker
    ];
    text = builtins.readFile ./scripts/rworker-nix.sh;
  };

  configLines = lib.concatStringsSep "\n" (
    lib.optional (cfg.controller != null) "controller=${cfg.controller}"
    ++ lib.optional (cfg.key != null) "key=${cfg.key}"
    ++ [
      "ttl=${cfg.ttl}"
      "system=${cfg.system}"
    ]
    ++ lib.optional (cfg.profile != null) "profile=${cfg.profile}"
  );
in
{
  options.fullNix.rworker = {
    enable = lib.mkEnableOption ''
      the optional `rworker-nix` command: it leases a disposable rworker, runs
      one `nix build|shell|develop` with `--max-jobs 0 --builders` against it
      (or `remote-build`, which also evaluates on the worker) and deletes the
      worker afterwards. The normal builders configuration is left alone'';

    controller = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "rworker-controller";
      description = ''
        SSH alias of the rworker controller. Its address and pinned host key
        belong in `~/.ssh/config` and `known_hosts` on the device; no
        hostname is stored in this repository. When null, set
        `RWORKER_NIX_CONTROLLER` or `controller=` in
        `~/.config/rworker-nix/config` yourself.
      '';
    };

    key = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/pschmitt/.ssh/id_ed25519.pub";
      description = ''
        Public SSH key file (must end in `.pub`) handed to the worker. Its
        private half is what Nix uses to log in. Null keeps the wrapper's
        default of `~/.ssh/id_ed25519.pub`.
      '';
    };

    ttl = lib.mkOption {
      type = lib.types.strMatching "([0-9]+[smhd])+|[0-9]+";
      default = "1h";
      description = "Lifetime of a worker; the backstop if cleanup cannot run.";
    };

    system = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9_]+-linux";
      default = pkgs.stdenv.hostPlatform.system;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.system";
      description = ''
        Platform the leased builder must build for. The worker has to run it
        natively or through qemu-user binfmt emulation, which the wrapper
        verifies before building.
      '';
    };

    profile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "rworker profile to lease; null uses the controller's default.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      rworker
      rworker-nix
    ];

    xdg.configFile."rworker-nix/config".text = configLines + "\n";
  };
}
