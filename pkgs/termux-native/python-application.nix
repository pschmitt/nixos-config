{
  lib,
  runCommand,
  package,
  python,
  entrypoint ? null,
  checkEntrypoint ? true,
  extraRuntimePackages ? [ ],
  excludedRuntimePackages ? [ ],
  extraFiles ? [ ],
}:
let
  packageName = lib.getName package;
  termuxName = "${packageName}-termux";
  command = (package.meta or { }).mainProgram or packageName;
  entrypointParts = if entrypoint == null then [ ] else lib.splitString ":" entrypoint;
  validIdentifier = value: builtins.match "[A-Za-z_][A-Za-z0-9_]*" value != null;
in
assert builtins.match "[A-Za-z0-9._+-]+" command != null;
assert entrypoint == null || builtins.length entrypointParts == 2;
assert
  entrypoint == null
  || builtins.all validIdentifier (lib.splitString "." (builtins.elemAt entrypointParts 0));
assert entrypoint == null || validIdentifier (builtins.elemAt entrypointParts 1);
runCommand "${termuxName}"
  {
    nativeBuildInputs = [ python ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      abi = "android-bionic";
      files = [ "bin/${command}" ] ++ extraFiles;
      binaries = [ ];
      scripts = [ "bin/${command}" ];
      trees = [ "python" ];
    };
    meta = (package.meta or { }) // {
      mainProgram = command;
    };
  }
  ''
    set -eu
    package_path=${lib.escapeShellArg (toString package)}
    export TERMUX_ADAPTER_SITE_PACKAGES="$package_path/${python.sitePackages}"
    export TERMUX_ADAPTER_COMMAND=${lib.escapeShellArg command}
    export TERMUX_ADAPTER_NAME=${lib.escapeShellArg termuxName}
    export TERMUX_ADAPTER_CHECK_ENTRYPOINT=${if checkEntrypoint then "1" else "0"}
    export TERMUX_ADAPTER_ENTRYPOINT=${
      lib.escapeShellArg (if entrypoint == null then "" else entrypoint)
    }
    export TERMUX_ADAPTER_OUTPUT="$out"
    mkdir -p "$out/python" "$out/bin"
    runtime_packages=(
      "$package_path"
      ${lib.escapeShellArgs (map toString extraRuntimePackages)}
    )
    excluded_runtime_packages=(
      ${lib.escapeShellArgs (map toString excludedRuntimePackages)}
    )
    declare -A runtime_seen=()
    declare -A runtime_excluded=()
    for runtime_package in "''${excluded_runtime_packages[@]}"
    do
      runtime_excluded["$runtime_package"]=1
    done
    for extra_file in ${lib.escapeShellArgs extraFiles}
    do
      source_file="$package_path/$extra_file"
      if [[ ! -f "$source_file" ]]
      then
        printf 'Python application extra file is missing: %s (%s)\\n' '${packageName}' "$extra_file" >&2
        exit 1
      fi
      mkdir -p "$out/$(dirname "$extra_file")"
      cp -L -- "$source_file" "$out/$extra_file"
    done
    package_found=0
    for ((package_index = 0; package_index < ''${#runtime_packages[@]}; package_index++))
    do
      runtime_package="''${runtime_packages[package_index]}"
      if [[ -n "''${runtime_excluded[$runtime_package]:-}" ]]
      then
        continue
      fi
      if [[ -n "''${runtime_seen[$runtime_package]:-}" ]]
      then
        continue
      fi
      runtime_seen["$runtime_package"]=1
      if [[ -r "$runtime_package/nix-support/propagated-build-inputs" ]]
      then
        propagated_packages=()
        read -r -a propagated_packages < "$runtime_package/nix-support/propagated-build-inputs" || :
        runtime_packages+=("''${propagated_packages[@]}")
      fi
      site_packages="$runtime_package/${python.sitePackages}"
      if [[ ! -d "$site_packages" ]]
      then
        continue
      fi
      [[ "$runtime_package" != "$package_path" ]] || package_found=1
      chmod -R u+w "$out/python"
      cp -RL -- "$site_packages/." "$out/python/"
    done
    if (( ! package_found ))
    then
      printf 'Python package has no installed site-packages: %s\\n' '${packageName}' >&2
      exit 1
    fi
    python - <<'PY'
    import configparser
    import importlib
    import os
    import pathlib
    import re
    import sys

    command = os.environ["TERMUX_ADAPTER_COMMAND"]
    package_name = os.environ["TERMUX_ADAPTER_NAME"]
    entrypoint = os.environ["TERMUX_ADAPTER_ENTRYPOINT"]
    check_entrypoint = os.environ["TERMUX_ADAPTER_CHECK_ENTRYPOINT"] == "1"
    site_packages = pathlib.Path(os.environ["TERMUX_ADAPTER_SITE_PACKAGES"])
    output = pathlib.Path(os.environ["TERMUX_ADAPTER_OUTPUT"])

    if entrypoint:
        module, function = entrypoint.split(":", maxsplit=1)
    else:
        matches = set()
        metadata_files = sorted(site_packages.glob("*.dist-info/entry_points.txt"))
        metadata_files += sorted(site_packages.glob("*.egg-info/entry_points.txt"))
        for metadata_file in metadata_files:
            parser = configparser.ConfigParser()
            parser.optionxform = str
            try:
                parser.read(metadata_file, encoding="utf-8")
                specification = parser.get("console_scripts", command, fallback=None)
            except (configparser.Error, UnicodeError) as error:
                print(f"Could not parse Python entry point metadata {metadata_file}: {error}", file=sys.stderr)
                sys.exit(1)
            if specification is not None:
                target = specification.split("[", maxsplit=1)[0].strip()
                if ":" not in target:
                    print(f"Unsupported Python entry point for {command}: {target}", file=sys.stderr)
                    sys.exit(1)
                matches.add(tuple(part.strip() for part in target.split(":", maxsplit=1)))
        if len(matches) != 1:
            print(
                f"Expected one console_scripts entry point named {command!r} in {site_packages}, found {len(matches)}; set entrypoint explicitly",
                file=sys.stderr,
            )
            sys.exit(1)
        module, function = matches.pop()

    identifier = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
    if not all(identifier.fullmatch(part) for part in module.split(".")) or not identifier.fullmatch(function):
        print(f"Unsupported Python entry point: {module}:{function}", file=sys.stderr)
        sys.exit(1)

    if check_entrypoint:
        sys.path.insert(0, str(output / "python"))
        try:
            entrypoint_object = getattr(importlib.import_module(module), function)
        except (ImportError, AttributeError) as error:
            print(f"Could not import Python entry point {module}:{function}: {error}", file=sys.stderr)
            sys.exit(1)
        if not callable(entrypoint_object):
            print(f"Python entry point is not callable: {module}:{function}", file=sys.stderr)
            sys.exit(1)

    wrapper = output / "bin" / command
    wrapper.write_text(
        "#!/data/data/com.termux/files/usr/bin/sh\n"
        "set -eu\n"
        ': "''${TERMUX_GENERATION:?TERMUX_GENERATION is not set}"\n'
        ': "''${PREFIX:?PREFIX is not set}"\n'
        f'export PYTHONPATH="$TERMUX_GENERATION/native/{package_name}/python''${{PYTHONPATH:+:$PYTHONPATH}}"\n'
        f'exec "$PREFIX/bin/python" -c \'from {module} import {function}; {function}()\' "$@"\n',
        encoding="utf-8",
    )
    wrapper.chmod(0o755)
    PY
    chmod -R u+w "$out/python"
    rm -f "$out/python/README.txt" "$out/python/sitecustomize.py"
    rm -f "$out/python"/_sysconfigdata_* "$out/python"/_sysconfig_vars_*
    find "$out/python" -type d -name __pycache__ -prune -exec rm -rf {} +
    find "$out/python" -type f \( -name '*.pyc' -o -name '*.pth' \) -delete
    if grep -R -I -n -F '/nix/store' "$out/python"; then
      printf 'Python runtime contains a Nix store reference: %s\\n' '${packageName}' >&2
      exit 1
    fi
  ''
