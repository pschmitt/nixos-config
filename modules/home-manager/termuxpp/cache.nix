{
  config,
  lib,
  pkgs,
  ...
}:
let
  cache = config.fullNix.upgradeCache;
in
{
  options.fullNix.upgradeCache = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          store = lib.mkOption { type = lib.types.str; };
          pin_reader = lib.mkOption { type = lib.types.str; };
          public_keys = lib.mkOption { type = lib.types.listOf lib.types.str; };
          credentials_file = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      }
    );
    default = null;
    description = "Signed binary cache and host-specific pin reader for nixpp upgrade.";
  };

  config.nix = lib.mkIf (cache != null) {
    settings = {
      extra-substituters = [ cache.store ];
      extra-trusted-public-keys = cache.public_keys;
    };

    package = lib.mkIf (cache.credentials_file != null) (
      pkgs.symlinkJoin {
        inherit (pkgs.nix) name;
        meta = pkgs.nix.meta // {
          outputsToInstall = [ "out" ];
        };
        paths = map (output: pkgs.nix.${output}) (pkgs.nix.meta.outputsToInstall or [ "out" ]);
        nativeBuildInputs = [ pkgs.makeWrapper ];
        # Nix is a multicall binary that dispatches on basename(argv[0]).
        # wrapProgram relies on `exec -a`, which PRoot drops, so nix-build
        # would run as `nix` in the guest. Exec a symlink that carries the
        # command name instead.
        postBuild = ''
          multicall="$out/libexec/nixpp-nix"
          mkdir -p "$multicall"
          for program in "$out"/bin/nix "$out"/bin/nix-*
          do
            if [[ -x "$program" ]]
            then
              name=''${program##*/}
              ln -s "$(readlink -f "$program")" "$multicall/$name"
              rm "$program"
              makeWrapper "$multicall/$name" "$program" \
                --set-default AWS_SHARED_CREDENTIALS_FILE ${lib.escapeShellArg cache.credentials_file}
            fi
          done
        '';
      }
    );
  };
}
