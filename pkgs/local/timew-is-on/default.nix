{
  writeShellApplication,
  timewarrior,
  gnugrep,
}:
writeShellApplication {
  name = "timew-is-on";
  runtimeInputs = [
    timewarrior
    gnugrep
  ];
  # Exit 0 when Timewarrior is actively tracking, non-zero otherwise.
  # Default the DB location so this works outside the interactive shell
  # (e.g. go-hass-agent systemd services), where TIMEWARRIORDB
  # would otherwise be unset and timew would read an empty default DB.
  text = ''
    export TIMEWARRIORDB="''${TIMEWARRIORDB:-$HOME/.config/timewarrior}"
    timew | grep -vq 'no active time tracking'
  '';
}
