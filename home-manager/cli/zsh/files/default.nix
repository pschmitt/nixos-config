# Local plugins and autoloaded functions of the Zsh config. The public trees
# here and any extra roots (programs.zsh.localConfig, set by the private repo)
# are merged into one store tree each (~/.config/zsh/{functions,plugins/local}),
# the functions are compiled into one digest and the plugins are bundled into
# one zcompiled file that config/runtime.nix loads.
{
  config,
  lib,
  pkgs,
  guiEnable ? false,
  ...
}:
let
  cfg = config.programs.zsh.localConfig;
  zsh = config.programs.zsh.package;

  pluginRoots = [ ./plugins/local ] ++ cfg.pluginDirs;
  functionRoots = [ ./functions ] ++ cfg.functionDirs;

  # Topics a host does not ship: their plugin (<topic>.zsh) and function
  # directory (<topic>/) are neither linked nor loaded.
  excluded = name: builtins.elem name cfg.excludeTopics;
  # zsh/functions/<topic>/... or zsh/plugins/local/<topic>.zsh
  excludedFile = f: excluded (lib.removeSuffix ".zsh" (lib.head (lib.splitString "/" f.rel)));

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

  # The files of several roots for one target, without excluded topics. The
  # roots share directories (functions/strings comes from both repos); a file
  # in several roots is an error.
  treeFiles =
    target: roots:
    let
      files = lib.filter (f: !excludedFile f) (
        lib.concatMap (
          root:
          let
            # One store copy per root (file names like a::b are no valid
            # store path names on their own)
            copy = builtins.path {
              path = root;
              name = "zsh-tree";
            };
          in
          map (f: f // { stored = "${copy}/${f.rel}"; }) (filesBelow root "")
        ) roots
      );
      duplicates = lib.attrNames (
        lib.filterAttrs (_: n: n > 1) (
          lib.foldl' (acc: f: acc // { ${f.rel} = (acc.${f.rel} or 0) + 1; }) { } files
        )
      );
    in
    assert lib.assertMsg (
      duplicates == [ ]
    ) "zsh: ${target} files defined in several roots: ${toString duplicates}";
    files;

  # File by file, for directories other modules add files to (completions)
  linkTree =
    target: roots:
    lib.listToAttrs (
      map (f: lib.nameValuePair "${target}/${f.rel}" { inherit (f) source; }) (treeFiles target roots)
    );

  # All files of the roots in one store directory: one home link instead of
  # one per file
  linkScript =
    files:
    lib.concatMapStrings (f: ''
      mkdir -p "$out/tree/"${lib.escapeShellArg (dirOf f.rel)}
      ln -s ${lib.escapeShellArg f.stored} "$out/tree/"${lib.escapeShellArg f.rel}
    '') files;

  functionFiles = treeFiles "zsh/functions" functionRoots;

  # The function tree (~/.config/zsh/functions) and its zcompiled digest:
  # fpath gets the empty directory fpath/, whose sibling fpath.zwc holds every
  # function, so `autoload -w` registers them all at once and they load as
  # wordcode. Compiled with the interactive lexer options, as the bundle.
  functions = pkgs.runCommand "zsh-functions" { nativeBuildInputs = [ zsh ]; } ''
    mkdir -p $out/fpath
    ${linkScript functionFiles}
    zsh -fc 'setopt EXTENDED_GLOB INTERACTIVE_COMMENTS RC_QUOTES; zcompile -Uz "$1" "$2"/**/*(-.)' \
      zsh $out/fpath.zwc $out/tree
  '';

  pluginTree = pkgs.runCommand "zsh-local-plugins-tree" { } ''
    ${linkScript (treeFiles "zsh/plugins/local" pluginRoots)}
  '';

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
              lib.filterAttrs (
                name: kind:
                kind != "directory" && lib.hasSuffix ".zsh" name && !excluded (lib.removeSuffix ".zsh" name)
              ) (builtins.readDir directory)
            )
        );
    in
    map (p: {
      function = "zpl::${lib.optionalString (group != "") "${group}::"}${lib.removeSuffix ".zsh" p.name}";
      inherit (p) source;
    }) (lib.sort (a: b: a.name < b.name) (lib.concatMap inGroup pluginRoots));
  plugins = lib.concatMap pluginsIn pluginGroups;

  # Register every function (one per file, named after it) from the digest.
  # Names that are already defined (by the rc, or by an earlier load when the
  # plugins are reloaded) would otherwise keep their old definition.
  registerFunctions = pkgs.writeText "zpl-functions.zsh" ''
    local -a names=(
      ${lib.concatMapStringsSep "\n  " (f: lib.escapeShellArg (baseNameOf f.rel)) functionFiles}
    )
    local -a defined=(''${(k)functions})
    defined=(''${names:*defined})
    (( ''${#defined} )) && unfunction -- $defined
    fpath=(${functions}/fpath ''${fpath:#*-zsh-functions/fpath})
    builtin autoload -Uz -w -- ${functions}/fpath.zwc
  '';

  # One file that defines a function per plugin (__zpl_manifest lists them in
  # load order), zcompiled next to it so sourcing it loads wordcode. As
  # functions, the plugins keep their `|| return` guards.
  pluginSources = map (p: {
    inherit (p) function;
    source = builtins.path {
      path = p.source;
      name = "zsh-plugin";
    };
  }) plugins;

  # programs.zsh.localConfig.prefixAliases, expanded at build time from the
  # names the function files and plugins define (./prefix-aliases.py).
  prefixAliases =
    pkgs.runCommand "zsh-prefix-aliases.zsh"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        spec = builtins.toJSON cfg.prefixAliases;
        functionNames = lib.concatMapStrings (f: baseNameOf f.rel + "\n") functionFiles;
        passAsFile = [
          "spec"
          "functionNames"
        ];
      }
      ''
        python3 ${./prefix-aliases.py} "$specPath" "$functionNamesPath" \
          ${lib.concatMapStringsSep " " (p: "${p.source}") pluginSources} > $out
      '';

  bundleSources = [
    {
      function = "__zpl_autoload_functions";
      source = registerFunctions;
    }
  ]
  ++ pluginSources
  ++ lib.optional (cfg.prefixAliases != [ ]) {
    function = "zpl::99-after::zz-prefix-aliases";
    source = prefixAliases;
  };

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
    excludeTopics = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "systemd" ];
      description = ''
        Topics this host does not ship: neither the plugin <topic>.zsh nor the
        functions in <topic>/ are installed or loaded. For hosts that lack a
        tool the plugin needs (the TermuxPP phones have no systemd), instead
        of a runtime `(( $+commands[tool] )) || return` guard.
      '';
    };
    prefixAliases = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            from = lib.mkOption {
              type = lib.types.str;
              example = "network::";
              description = "Prefix of the existing function and alias names.";
            };
            to = lib.mkOption {
              type = lib.types.str;
              example = "net::";
              description = "Prefix that replaces it in the new names.";
            };
            kind = lib.mkOption {
              type = lib.types.enum [
                "alias"
                "function"
              ];
              default = "alias";
              description = ''
                An alias, or a wrapper function (works in scripts and other
                functions; not created when that name is already a function).
              '';
            };
            env = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "OPENSTACK_BIN=openstack-fec";
              description = "Assignments a wrapper function puts before the call.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Name aliases generated at build time, after all local plugins: for
        every function or alias FROM<rest> that a function file or plugin
        defines, TO<rest> calls it.
      '';
    };
    completionDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Directories of completion functions for ~/.config/zsh/completions.";
    };
  };

  # Desktop session tools (Hyprland, Wayland, X, audio, ...) only exist on
  # GUI hosts: servers and the phones do not ship these topics.
  config.programs.zsh.localConfig.excludeTopics = lib.mkIf (!guiEnable) [
    "display-manager"
    "dms"
    "hyprland"
    "imv"
    "lockscreen"
    "mako"
    "mouse"
    "noctalia"
    "obs"
    "pipewire"
    "pulseaudio"
    "screenshot"
    "sway"
    "waybar"
    "wayland"
    "wayvnc"
    "window-manager"
    "xkb"
    "xorg"
    "ydotool"
  ];

  config.xdg.configFile = linkTree "zsh/completions" cfg.completionDirs // {
    "zsh/functions".source = "${functions}/tree";
    "zsh/plugins/local".source = "${pluginTree}/tree";
    "zsh/plugins/local.zsh".source = "${bundle}/local.zsh";
    "zsh/plugins/local.zsh.zwc".source = "${bundle}/local.zsh.zwc";
    "zsh/static/README.md".source = ./static/README.md;
  };
}
