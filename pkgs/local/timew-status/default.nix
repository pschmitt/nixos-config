{
  lib,
  symlinkJoin,
  timew-is-on,
  timew-total,
  timew-week-breakdown,
}:
symlinkJoin {
  name = "timew-status";
  paths = [
    timew-is-on
    timew-total
    timew-week-breakdown
  ];
  meta = {
    description = "Timewarrior status helpers (timew-is-on, timew-total, timew-week-breakdown)";
    license = lib.licenses.gpl3Only;
    maintainers = [ lib.maintainers.pschmitt ];
    platforms = lib.platforms.linux;
  };
}
