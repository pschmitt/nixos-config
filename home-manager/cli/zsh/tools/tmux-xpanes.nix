{
  inputs,
  pkgs,
  ...
}:
let
  xpanes = pkgs.runCommand "tmux-xpanes" { } ''
    install -Dm755 ${inputs.tmux-xpanes}/bin/xpanes "$out/bin/xpanes"
    ln -s xpanes "$out/bin/tmux-xpanes"
    install -Dm644 ${inputs.tmux-xpanes}/man/xpanes.1 "$out/share/man/man1/xpanes.1"
  '';
in
{
  home.packages = [ xpanes ];
  xdg.configFile."tmux/bin/xpanes".source = "${xpanes}/bin/xpanes";
}
