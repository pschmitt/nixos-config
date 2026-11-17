{ pkgs }:
pkgs.writeShellApplication {
  name = "obs-register-script";
  text = ''
    exec ${pkgs.python3}/bin/python3 -I ${./obs-register-script.py} "$@"
  '';
}
