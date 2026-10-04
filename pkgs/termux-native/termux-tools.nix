{
  gnused,
  lib,
  package,
  runCommand,
}:
let
  scripts = builtins.attrNames (
    lib.filterAttrs (
      name: type:
      type == "regular"
      && (lib.hasPrefix "termux_" name || lib.hasPrefix "termux-" name)
      && lib.hasSuffix ".sh" name
    ) (builtins.readDir "${package}/scripts")
  );
  commands = map (
    name:
    lib.removeSuffix ".sh" (
      if lib.hasPrefix "termux_" name then lib.removePrefix "termux_" name else name
    )
  ) scripts;
  exportedScripts = map (command: "bin/${command}") commands;
in
assert scripts != [ ];
runCommand "termux-tools"
  {
    nativeBuildInputs = [ gnused ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      abi = "android-bionic";
      files = exportedScripts;
      binaries = [ ];
      scripts = exportedScripts;
      trees = [ ];
    };
    meta = {
      description = "Personal Termux helper commands packaged for native Termux";
      mainProgram = "termux-display";
    };
  }
  ''
    mkdir -p "$out/bin"
    for source in ${lib.escapeShellArgs (map (name: "${package}/scripts/${name}") scripts)}
    do
      filename="''${source##*/}"
      command="''${filename#termux_}"
      command="''${command%.sh}"
      {
        printf '%s\n' '#!/data/data/com.termux/files/usr/bin/bash'
        sed '1d' "$source"
      } > "$out/bin/$command"
      chmod 0755 "$out/bin/$command"
    done
  ''
