# Restart helper for PipeWire/WirePlumber config `onChange` hooks; skips the
# restart while the Meeting Microphone is in use (see the script).
pkgs:
pkgs.writeShellApplication {
  name = "restart-audio";
  runtimeInputs = [
    pkgs.jq
    pkgs.pipewire
    pkgs.systemd
  ];
  text = builtins.readFile ./scripts/restart-audio.sh;
}
