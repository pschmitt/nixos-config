{
  # 2025-11-17 disable orca since it was autostarted by:
  # https://github.com/NixOS/nixpkgs/pull/461953
  # ref: https://github.com/YaLTeR/niri/issues/2830
  systemd.user.services.orca.enable = false;
}
