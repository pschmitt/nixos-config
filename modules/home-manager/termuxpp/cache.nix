{
  config,
  lib,
  pkgs,
  ...
}:
let
  cache = config.nixpp.upgradeCache;
in
{
  options.nixpp.upgradeCache = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          store = lib.mkOption { type = lib.types.str; };
          pin_reader = lib.mkOption { type = lib.types.str; };
          public_keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            # Our caches' keys, shared with the NixOS hosts, plus the S3 cache's.
            default = import ../../../profiles/base/nix-cache-keys.nix ++ [
              "nix-cache.brkn.lol:k/zdgSv+6lcJ/9DRILjA7H18eIlFSA0OwzyqqXEwySM="
            ];
          };
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
        # wrapProgram relies on `exec -a`, which the guest launcher's re-exec
        # drops, so nix-build would run as `nix`. Exec a symlink that carries
        # the command name instead. Link every program before wrapping any:
        # the nix-* links resolve through bin/nix, which becomes a wrapper.
        postBuild = ''
          multicall="$out/libexec/nixpp-nix"
          mkdir -p "$multicall"
          programs=()
          for program in "$out"/bin/nix "$out"/bin/nix-*
          do
            if [[ -x "$program" ]]
            then
              ln -s "$(readlink -f "$program")" "$multicall/''${program##*/}"
              programs+=("$program")
            fi
          done
          for program in "''${programs[@]}"
          do
            rm "$program"
            makeWrapper "$multicall/''${program##*/}" "$program" \
              --set-default AWS_SHARED_CREDENTIALS_FILE ${lib.escapeShellArg cache.credentials_file}
          done
        '';
      }
    );
  };
}
