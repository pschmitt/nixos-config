{ pkgs, ... }:
{
  home.packages = with pkgs; [
    taskwarrior3
    timew-sync-client
    timewarrior
    timewarrior-jirapush
    python312Packages.bugwarrior
  ];
}
