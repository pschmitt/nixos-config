# Nix port of the yadm ~/bin/pycolumn uv script (column -t with ANSI and
# wide-character aware widths).
{
  lib,
  python3,
  writeScriptBin,
}:
let
  python = python3.withPackages (ps: [
    ps.regex
    ps.wcwidth
  ]);
in
(writeScriptBin "pycolumn" ''
  #!${python}/bin/python3
  ${builtins.readFile ./pycolumn.py}
'')
// {
  meta = {
    description = "column -t replacement aware of ANSI colors and wide characters";
    license = lib.licenses.gpl3Only;
    mainProgram = "pycolumn";
  };
}
