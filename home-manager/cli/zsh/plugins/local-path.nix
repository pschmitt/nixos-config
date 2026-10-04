{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1360 ''
    zsh::override-local-path() {
      print_path() {
        local missing_only
        zparseopts -K -D m=missing_only

        local p
        for p in "''${path[@]}"
        do
          if [[ -n "$missing_only" && ! -d "$p" ]]
          then
            print -r -- "\"$p\" does not exist" >&2
          else
            print -r -- "$p"
          fi
        done
      }
    }
  '';
}
