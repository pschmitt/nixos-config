{ final, prev }:
{
  # zstd-sys and libsqlite3-sys need pkg-config and their system libraries.
  # Local fix: remove when Nixpkgs supplies these inputs. Reviewed 2026-11-10
  # at f4a03c008967841f2a0b3cb7c436fc6fc31671f6: unpatched build fails,
  # and the patched package builds successfully on x86_64-linux.
  taskchampion-sync-server = prev.taskchampion-sync-server.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
    buildInputs = (old.buildInputs or [ ]) ++ [
      final.sqlite
      final.zstd
    ];
  });
}
