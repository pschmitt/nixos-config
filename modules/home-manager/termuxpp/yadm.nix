{
  config,
  lib,
  pkgs,
  ...
}:
let
  yadm = lib.getExe pkgs.yadm;
in
{
  home.activation.yadmRemoveTermuxppClass = lib.hm.dag.entryAfter [ "androidAcceptance" ] ''
    if [[ -d ${lib.escapeShellArg "${config.xdg.dataHome}/yadm/repo.git"} ]] &&
      ${yadm} config --get-all local.class '^termuxpp$' >/dev/null
    then
      run ${yadm} config --unset-all local.class '^termuxpp$'
    fi
  '';
}
