{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixpp.rworker;

  # crane takes build tools such as rsync from the package set it is made
  # for; the guest's patched rsync would make the compiled client differ from
  # the one rworker's CI pins for our nixpkgs. Compile with plain nixpkgs; the
  # wrapper still puts the guest's rsync on PATH.
  plainPkgs = inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  rworker = pkgs.rworker.override {
    craneLib = inputs.rworker.inputs.crane.mkLib plainPkgs;
    extraRuntimeInputs = [ pkgs.hostname ];
    sshControlMaster = false;
  };

  # A bare `rworker up|exec|setup nix` pushes the S3 cache only when it finds
  # the cache's AWS profile; default to the one the system upgrades use.
  rworkerCommand =
    if cfg.awsCredentialsFile == null then
      rworker
    else
      pkgs.symlinkJoin {
        name = "${rworker.name}-cache-credentials";
        paths = [ rworker ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/rworker \
            --set-default RWORKER_AWS_CREDENTIALS_FILE ${lib.escapeShellArg cfg.awsCredentialsFile}
        '';
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
    ++ lib.optional (cfg.awsCredentialsFile != null) "aws_credentials=${cfg.awsCredentialsFile}"
    ++ [
      "ttl=${cfg.ttl}"
      "system=${cfg.system}"
    ]
    ++ lib.optional (cfg.profile != null) "profile=${cfg.profile}"
  );
in
{
  # The option namespace used to be fullNix; nixos-config-private still sets it.
  imports = [
    (lib.mkRenamedOptionModule [ "fullNix" "rworker" "controller" ] [ "nixpp" "rworker" "controller" ])
  ];

  options.nixpp.rworker = {
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
      description = ''
        rworker profile to lease. With null, local evaluation prefers the
        target architecture and uses the controller default when the native
        pool is unavailable. Remote evaluation uses the controller default
        for private flake and cache access.
      '';
    };

    awsCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if config.nixpp.upgradeCache != null then config.nixpp.upgradeCache.credentials_file else null;
      defaultText = lib.literalExpression "config.nixpp.upgradeCache.credentials_file";
      description = ''
        Read-only AWS credentials of the private `s3://` substituter. With
        them, `rworker-nix remote-build` (nixpp `--remote-eval`) lets the
        worker substitute from that cache; without, the worker builds what no
        public cache has, and outputs that only exist there cannot be built.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      rworkerCommand
      rworker-nix
    ];

    xdg.configFile."rworker-nix/config".text = configLines + "\n";
  };
}
