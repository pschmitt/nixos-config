{
  lib,
  symlinkJoin,
  timew-is-on,
  timew-total,
}:
symlinkJoin {
  name = "timew-status";
  paths = [
    timew-is-on
    timew-total
  ];
  meta = {
    description = "Timewarrior status helpers (timew-is-on, timew-total)";
    license = lib.licenses.gpl3Only;
    maintainers = [ lib.maintainers.pschmitt ];
    platforms = lib.platforms.linux;
  };
}
