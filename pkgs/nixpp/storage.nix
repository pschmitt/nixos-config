{ coreutils, writeShellApplication }:
writeShellApplication {
  name = "termux-setup-storage";
  runtimeInputs = [ coreutils ];
  text = builtins.readFile ./scripts/setup-storage.sh;
}
