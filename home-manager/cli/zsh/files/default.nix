# Local plugins and autoloaded functions of the Zsh config. The public trees
# here and any extra roots (programs.zsh.localConfig, set by the private repo)
# are linked file by file into ~/.config/zsh and the plugins are bundled into
# one zcompiled file that config/runtime.nix loads.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.zsh.localConfig;
  zsh = config.programs.zsh.package;

  pluginRoots = [ ./plugins/local ] ++ cfg.pluginDirs;
  functionRoots = [ ./functions ] ++ cfg.functionDirs;

  # Files below a directory: [ { rel = "a/b"; source = <path>; } ]
  filesBelow =
    directory: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: kind:
        let
          rel = if prefix == "" then name else "${prefix}/${name}";
          source = directory + "/${name}";
        in
        if kind == "directory" then
          filesBelow source rel
        else if kind == "regular" || kind == "symlink" then
          [ { inherit rel source; } ]
        else
          [ ]
      ) (builtins.readDir directory)
    );

  # The roots share their targets (zsh/functions/strings comes from both
  # repos), so link every file on its own. A file in several roots is an error.
  linkTree =
    target: roots:
    let
      files = lib.concatMap (root: filesBelow root "") roots;
      duplicates = lib.attrNames (
        lib.filterAttrs (_: n: n > 1) (
          lib.foldl' (acc: f: acc // { ${f.rel} = (acc.${f.rel} or 0) + 1; }) { } files
        )
      );
    in
    assert lib.assertMsg (
      duplicates == [ ]
    ) "zsh: ${target} files defined in several roots: ${toString duplicates}";
    lib.listToAttrs (map (f: lib.nameValuePair "${target}/${f.rel}" { inherit (f) source; }) files);

  functionFiles = lib.concatMap (root: filesBelow root "") functionRoots;

  # Plugins in load order: the root, work/ and 99-after/, each sorted by name
  # across all roots. Each becomes a function zpl::<group::>name in the digest.
  pluginGroups = [
    ""
    "work"
    "99-after"
  ];
  pluginsIn =
    group:
    let
      inGroup =
        root:
        let
          directory = if group == "" then root else root + "/${group}";
        in
        lib.optionals (builtins.pathExists directory) (
          lib.mapAttrsToList
            (name: _: {
              inherit name;
              source = directory + "/${name}";
            })
            (
              lib.filterAttrs (name: kind: kind != "directory" && lib.hasSuffix ".zsh" name) (
                builtins.readDir directory
              )
            )
        );
    in
    map (p: {
      function = "zpl::${lib.optionalString (group != "") "${group}::"}${lib.removeSuffix ".zsh" p.name}";
      inherit (p) source;
    }) (lib.sort (a: b: a.name < b.name) (lib.concatMap inGroup pluginRoots));
  plugins = lib.concatMap pluginsIn pluginGroups;

  functionsDir = "${config.xdg.configHome}/zsh/functions";

  # Autoload every function file (one function per file, named after it).
  # Names that are already defined (by the rc, or by an earlier load when the
  # plugins are reloaded) would otherwise keep their old definition.
  registerFunctions = pkgs.writeText "zpl-functions.zsh" ''
    local -a files=(
      ${lib.concatMapStringsSep "\n  " (f: lib.escapeShellArg f.rel) functionFiles}
    )
    files=(${lib.escapeShellArg functionsDir}/''${^files})
    local -a names=(''${files:t}) defined=(''${(k)functions})
    defined=(''${names:*defined})
    (( ''${#defined} )) && unfunction -- $defined
    builtin autoload -Uz -- $files
  '';

  # One file that defines a function per plugin (__zpl_manifest lists them in
  # load order), zcompiled next to it so sourcing it loads wordcode. As
  # functions, the plugins keep their `|| return` guards.
  bundleSources = [
    {
      function = "__zpl_autoload_functions";
      source = registerFunctions;
    }
  ]
  ++ map (p: {
    inherit (p) function;
    source = builtins.path {
      path = p.source;
      name = "zsh-plugin";
    };
  }) plugins;

  # zcompile parses at build time, so it needs the lexer options of the
  # interactive shell (config/base.nix): plugins rely on RC_QUOTES ('').
  bundle = pkgs.runCommand "zsh-local-plugins" { nativeBuildInputs = [ zsh ]; } ''
    mkdir -p $out
    {
      printf '__zpl_manifest() {\n  __zpl_plugins=(\n'
      ${lib.concatMapStrings (p: ''
        printf '    %s\n' ${lib.escapeShellArg p.function}
      '') bundleSources}
      printf '  )\n}\n'
      ${lib.concatMapStrings (p: ''
        printf '\n%s() {\n' ${lib.escapeShellArg p.function}
        cat ${p.source}
        printf '\n}\n'
      '') bundleSources}
    } > $out/local.zsh
    cd $out
    zsh -fc 'setopt EXTENDED_GLOB INTERACTIVE_COMMENTS RC_QUOTES; zcompile -U local.zsh'
  '';
in
{
  options.programs.zsh.localConfig = {
    pluginDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Extra local plugin roots: *.zsh files in the root, work/ and 99-after/,
        loaded together with the public ones (sorted by name per directory).
      '';
    };
    functionDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Extra autoloaded function roots (<topic>/<function> files).";
    };
    completionDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Directories of completion functions for ~/.config/zsh/completions.";
    };
  };

  config.xdg.configFile =
    linkTree "zsh/functions" functionRoots
    // linkTree "zsh/plugins/local" pluginRoots
    // linkTree "zsh/completions" cfg.completionDirs
    // {
      "zsh/plugins/local.zsh".source = "${bundle}/local.zsh";
      "zsh/plugins/local.zsh.zwc".source = "${bundle}/local.zsh.zwc";
      "zsh/static/README.md".source = ./static/README.md;
    };
}
