{
  final,
  # inputs,
  prev,
  ...
}:

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

      # parsedmarc is incompatible with (and marked broken against)
      # msgraph-core >= 1.0; pin the old msgraph-core just for it.
      # https://github.com/domainaware/parsedmarc/issues/464
      parsedmarc = prevPy.parsedmarc.override {
        msgraph-core = msgraph-core-022;
      };
    }
  );

  # NixOS module uses pkgs.parsedmarc, not pkgs.python313Packages.parsedmarc.
  inherit (final.python313Packages) parsedmarc pipx;

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

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;
}
