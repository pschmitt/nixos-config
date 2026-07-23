{
  config,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = with pkgs; [
    aapt # aapt2, e.g. `aapt2 dump badging some.apk`
    android-tools # adb + fastboot
    inputs.declaroid.packages.${system}.default # declarative app provisioning, see https://github.com/pschmitt/declaroid
    inputs.tsvtool.packages.${system}.default # pretty TSV/JSON/YAML/TOML tables, used by declaroid's devices/diff output
    pmbootstrap
  ];

  # Points at the live checkout, not a Nix-store copy: android/all.yaml's
  # `configs:` entries (mp4.yaml/px5.yaml/zf10.yaml) are relative paths
  # resolved against the config file's own directory, which only exists in
  # the real repo -- a xdg.configFile-templated store copy of all.yaml
  # would have no sibling device files to find. Same live-checkout
  # convention already used by home-manager/devel/ai.nix's
  # claude-code-trusted-workspaces entry. Takes priority over
  # xdg.configFile's apps.yaml below (declaroid's own config resolution
  # order: --config, $DECLAROID_CONFIG, ~/.config/declaroid/apps.yaml),
  # which stays as a fallback for contexts that don't source session
  # variables (cron, a non-login shell, ...) -- a bare `declaroid apply`
  # there safely falls back to the small shared baseline instead of
  # silently having no config at all.
  home.sessionVariables.DECLAROID_CONFIG = "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git/android/all.yaml";

  xdg.configFile."declaroid/apps.yaml".source = ../../android/imports/apps.yaml;
}
