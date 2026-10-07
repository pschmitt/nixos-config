# Nix port of the yadm ~/bin/zebra uv script (zebra-striped table output).
{
  lib,
  python3,
  writeScriptBin,
}:
let
  python = python3.withPackages (ps: [ ps.wcwidth ]);
in
(writeScriptBin "zebra" ''
  #!${python}/bin/python3
  ${builtins.readFile ./zebra.py}
'')
// {
  meta = {
    description = "Zebra-stripe tabular output with background colors";
    license = lib.licenses.gpl3Only;
    mainProgram = "zebra";
  };
}
