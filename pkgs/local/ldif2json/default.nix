# Nix port of the yadm ~/bin/ldif2json gawk script (LDIF to JSON, used by the
# ldap:: zsh functions).
{
  lib,
  gawk,
  writeScriptBin,
}:
(writeScriptBin "ldif2json" ''
  #!${gawk}/bin/gawk -f
  ${builtins.readFile ./ldif2json.awk}
'')
// {
  meta = {
    description = "Convert LDIF into JSON";
    license = lib.licenses.mit;
    mainProgram = "ldif2json";
  };
}
