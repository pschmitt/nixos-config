{ final, prev }:
{
  # taskchampion links system SQLite with current Rust build hooks. Local fix;
  # remove when Nixpkgs supplies it. Reviewed 2026-11-10 at
  # f4a03c008967841f2a0b3cb7c436fc6fc31671f6: the unpatched link fails.
  taskwarrior3 = prev.taskwarrior3.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
    buildInputs = (old.buildInputs or [ ]) ++ [ final.sqlite ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/CMakeLists.txt \
        --replace-fail 'target_link_libraries(task taskchampion-cpp)' \
          'target_link_libraries(task taskchampion-cpp sqlite3)'
    '';
  });
}
