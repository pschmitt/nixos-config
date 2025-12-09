# This file is required for gitUpdater (and other legacy updaters) to work.
# It allows update-source-version to find packages in this flake-based repo.
let
  flake = builtins.getFlake (toString ./.);
in
flake.packages.${builtins.currentSystem}
