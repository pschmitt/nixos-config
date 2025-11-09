{ pkgs, lib, ... }:
let
  bashCompleteAliases = pkgs.fetchurl {
    url = "https://github.com/cykerway/complete-alias/raw/1.18.0/complete_alias";
    sha256 = "sha256-klo2tWCUyg5s6GrrxPdSSDjF6pz6E1lBeiCLu3A/4cc=";
  };
in
{

  programs.bash = {
    vteIntegration = true;
    # blesh.enable = false; # disable ble.sh, we want a custom RC file
    interactiveShellInit = ''
      source ${bashCompleteAliases}
      # blesh is disabled
      # (( UID )) && source ${pkgs.blesh}/share/blesh/ble.sh --rcfile /etc/bleshrc
    '';
  };

  environment = {
    etc.bashrc.text = lib.mkAfter ''
      if [ -n "$PS1" ]; then
        complete -F _complete_alias "''${!BASH_ALIASES[@]}"
      fi
    '';

    etc.bleshrc.text = ''
      # Disable error exit marker like "[ble: exit %d]"
      bleopt exec_errexit_mark=
      # Disable elapsed-time marker like "[ble: elapsed 1.203s (CPU 0.4%)]"
      bleopt exec_elapsed_mark=
      # FIXME: This is not recognized by our version of ble.sh
      # Disable exit marker like "[ble: exit]"
      # bleopt exec_exit_mark=
      # Disable highlighting based on filenames
      bleopt highlight_filename=
    '';
  };
}
