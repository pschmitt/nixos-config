{
  final,
  # inputs,
  prev,
  ...
}:

let
  # GitLab's v4.6.5 archive was repacked upstream, so the fixed-output hash in
  # nixpkgs no longer matches the downloaded source tarball.
  fixWiresharkHash =
    pkg:
    pkg.overrideAttrs (old: {
      src = prev.fetchFromGitLab {
        owner = "wireshark";
        repo = "wireshark";
        tag = "v${old.version}";
        hash = "sha256-Zvrwxjp4LK2J3QnxmPxKKrU01YHQvPyp54UWzeGNCjA=";
      };
    });
in
{
  python313Packages = prev.python313Packages.overrideScope (
    finalPy: prevPy:
    let
      msgraph-core-022 = finalPy.buildPythonPackage rec {
        pname = "msgraph-core";
        version = "0.2.2";
        format = "setuptools";

        src = prev.fetchPypi {
          inherit pname version;
          hash = "sha256-FHMkJGeIq+jtfgVTTNnk4OyYszsw4BFpO40BTOv5f2M=";
        };

        nativeBuildInputs = [ finalPy.setuptools ];
        dependencies = [ finalPy.requests ];
        pythonImportsCheck = [ "msgraph.core" ];
      };
    in
    {
      pipx = prevPy.pipx.overridePythonAttrs (old: {
        # pipx 1.8.0 has Python 3.13 test expectation mismatches for
        # package-specifier normalization; keep the package buildable until
        # the nixpkgs fix lands.
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_fix_package_name"
          "test_parse_specifier_for_metadata"
        ];
      });

      parsedmarc =
        (prevPy.parsedmarc.override {
          msgraph-core = msgraph-core-022;
        }).overridePythonAttrs
          (old: {
            version = "9.1.1";
            src = prev.fetchFromGitHub {
              owner = "domainaware";
              repo = "parsedmarc";
              tag = "9.1.1";
              hash = "sha256-T2TcO3KkNbM37O59aXtDPfrLAktKjSJfZTITcS2SYM0=";
            };
            dependencies = (old.dependencies or [ ]) ++ [ finalPy.pyyaml ];
            # nixpkgs carries a version-specific substitution that no longer
            # matches against the GitHub tag source.
            postPatch = ''
              sed -i '/^requires_python = /d' pyproject.toml
            '';
          });
    }
  );

  # NixOS module uses pkgs.parsedmarc, not pkgs.python313Packages.parsedmarc.
  inherit (final.python313Packages) parsedmarc pipx;

  wireshark = fixWiresharkHash prev.wireshark;
  wireshark-cli = fixWiresharkHash prev.wireshark-cli;

  # Waybar's hyprland/workspaces module hard-codes old Hyprlang-style
  # dispatchers ("dispatch workspace N") which are invalid Lua and fail
  # in Hyprland Lua config mode (configType = "lua").
  # TODO: remove once Waybar ships native Lua dispatch support.
  waybar = prev.waybar.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/modules/hyprland/workspace.cpp \
        --replace-fail \
          'dispatch focusworkspaceoncurrentmonitor " + std::to_string(id())' \
          'dispatch hl.dsp.focus({ workspace = " + std::to_string(id()) + ", monitor = \"current\" })"' \
        --replace-fail \
          'dispatch workspace " + std::to_string(id())' \
          'dispatch hl.dsp.focus({ workspace = " + std::to_string(id()) + " })"' \
        --replace-fail \
          'dispatch focusworkspaceoncurrentmonitor name:" + name()' \
          'dispatch hl.dsp.focus({ workspace = \"name:" + name() + "\", monitor = \"current\" })"' \
        --replace-fail \
          'dispatch workspace name:" + name()' \
          'dispatch hl.dsp.focus({ workspace = \"name:" + name() + "\" })"' \
        --replace-fail \
          'dispatch togglespecialworkspace " + name()' \
          'dispatch hl.dsp.workspace.toggle_special({ name = \"" + name() + "\" })"' \
        --replace-fail \
          '"dispatch togglespecialworkspace"' \
          '"dispatch hl.dsp.workspace.toggle_special()"'
    '';
  });

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/xxx reaches
  # nixos-unstable
  # inherit (inputs.nixpkgs-xxx.legacyPackages.${final.stdenv.hostPlatform.system}) PKGNAME;

  # https://github.com/NixOS/nixpkgs/pull/522784 — termite removed (dead
  # upstream); vte 0.84.0 fails to build in the meantime.  The NixOS
  # terminfo module does `map (x: x.terminfo)` over all packages, so the
  # stub must carry a `terminfo` attribute (an empty dir is fine).
  # TODO: Remove once nixpkgs#522784 reaches nixos-unstable.
  termite =
    let
      terminfo = prev.runCommand "termite-noop-terminfo" { } "mkdir -p $out/share/terminfo";
    in
    (prev.runCommand "termite-noop" { } "mkdir $out") // { inherit terminfo; };

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;
}
