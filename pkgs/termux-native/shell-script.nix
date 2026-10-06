{
  lib,
  runCommand,
  name,
  script,
  supportFiles ? [ ],
  scriptReplacements ? [ ],
  aptPackages ? [ ],
  description,
  homepage,
  license,
}:
let
  command = builtins.baseNameOf script;
  scriptPath = "bin/${command}";
  supportPaths = map (file: file.target) supportFiles;
in
assert builtins.match "[A-Za-z0-9._+-]+" command != null;
runCommand "${name}-termux"
  {
    allowedReferences = [ ];
    passthru.termuxNative = {
      abi = "android-bionic";
      inherit aptPackages;
      binaries = [ ];
      files = [ scriptPath ] ++ supportPaths;
      scripts = [ scriptPath ];
      trees = [ ];
    };
    meta = {
      inherit
        description
        homepage
        license
        ;
      mainProgram = command;
      platforms = lib.platforms.linux;
    };
  }
  ''
    install -Dm755 ${lib.escapeShellArg (toString script)} "$out/${scriptPath}"
    ${lib.concatMapStringsSep "\n" (replacement: ''
      substituteInPlace "$out/${scriptPath}" \
        --replace-fail \
        ${lib.escapeShellArg replacement.from} \
        ${lib.escapeShellArg replacement.to}
    '') scriptReplacements}
    ${lib.concatMapStringsSep "\n" (file: ''
      install -Dm644 \
        ${lib.escapeShellArg (toString file.source)} \
        "$out/${file.target}"
    '') supportFiles}
  ''
