_: {
  programs.zsh = {
    shellGlobalAliases = {
      DN = "&> /dev/null";
      L = "| less";
      J = "| jq";
      Yy = "| bat -l yaml --style=numbers";
      NOP = "; () { local rc=\"$?\"; [[ \"$rc\" == 0 ]] && echo_ok OK || echo_err \"NOPE. RC=$rc\"; return \"$rc\"; }";
      TC = "| tee >(cat)";
    };
    shellAliases = {
      y = "nix search nixpkgs";
      ync = "nix-shell --packages";
    };
    initContent = ''
      for extension in html org php com net de fr png jpg gif; do
        alias -s "$extension"="$BROWSER"
      done
      for extension in sxw doc; do
        alias -s "$extension"=soffice
      done
      for extension in c cpp h hpp java txt PKGBUILD; do
        alias -s "$extension"="$EDITOR"
      done
      unset extension
    '';
  };
}
