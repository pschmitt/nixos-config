{
  final,
  # inputs,
  prev,
  ...
}:

{
  python313Packages = prev.python313Packages.overrideScope (
    _finalPy: prevPy: {
      pipx = prevPy.pipx.overridePythonAttrs (old: {
        # pipx has Python 3.13 test expectation mismatches for package-specifier
        # normalization.  Version 1.14.0 also passes a bare string to pytest's
        # single-parameter parametrization, which pytest 9 rejects during
        # collection.  Keep the package buildable until the nixpkgs fixes land.
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_fix_package_name"
          "test_parse_specifier_for_metadata"
        ];
        # pipx 1.14.0's tests/test_inject.py has a stray trailing comma in
        # `@pytest.mark.parametrize("pkg_spec,", ...)`, which breaks
        # parametrize collection under nixpkgs' newer pytest -- a collection
        # error, not a deselectable test failure, so nixpkgs' own
        # disabledTests ("inject" via -k) can't rescue it. Skip the whole
        # file until upstream fixes the typo.
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
          "tests/test_inject.py"
        ];
      });

      python-aodhclient = prevPy.python-aodhclient.overridePythonAttrs (_: {
        # nixpkgs sets pname = "python-aodhclient" (the GitHub repo name),
        # but upstream's pyproject.toml declares name = "aodhclient", so the
        # generic pythonMetadataCheckPhase looks up a dist-info that doesn't
        # exist under that name and fails every build. Pulled in transitively
        # by openstackclient-full; remove once the nixpkgs pname is fixed.
        dontCheckPythonMetadata = true;
      });
    }
  );

  inherit (final.python313Packages) pipx;

  pytr = prev.pytr.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      python - <<'PY'
      from pathlib import Path

      path = Path("pytr/api.py")
      text = path.read_text()
      text = text.replace("import subprocess\n", "")
      text = text.replace("import ssl\n", "import shutil\nimport ssl\n")
      launch_block = """                    browser = p.chromium.launch(
                              headless=True,
                              args=[\"--no-sandbox\", \"--disable-setuid-sandbox\"],
                          )
      """
      install_block = """                else:
                          self.log.warning(\"%s\", e)
                          self.log.info('Running \"playwright install chromium\"...')
                          called_playwright_install = True
                          done = False
                          subprocess.run([\"playwright\", \"install\", \"chromium\"], check=True)
                          self.log.info(\"Calling Playwright once more...\")
      """
      if launch_block not in text or install_block not in text:
          raise SystemExit("pytr Playwright patch no longer matches upstream source")
      text = text.replace(
          launch_block,
          """                    browser_executable = next(
                              (
                                  executable
                                  for executable in (
                                      shutil.which(\"chromium\"),
                                      shutil.which(\"google-chrome-stable\"),
                                      shutil.which(\"google-chrome\"),
                                      shutil.which(\"chrome\"),
                                  )
                                  if executable
                              ),
                              None,
                          )
                          if browser_executable is None:
                              raise RuntimeError(
                                  \"No Chromium-compatible browser found on PATH. \"
                                  \"Install pkgs.chromium instead of running playwright install.\"
                              )
                          browser = p.chromium.launch(
                              executable_path=browser_executable,
                              headless=True,
                              args=[\"--no-sandbox\", \"--disable-setuid-sandbox\"],
                          )
      """,
      )
      text = text.replace(
          install_block,
          """                else:
                          self.log.error(\"Failed to launch Playwright using a browser from PATH.\")
                          raise
      """,
      )
      path.write_text(text)
      PY
    '';
  });

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

  # perl5.42.0-DBD-CSV-0.60 fails 3 tests in t/70_csv.t; disable until
  # upstream fix lands in nixpkgs.
  perlPackages = prev.perlPackages.overrideScope (
    _finalPerl: prevPerl: {
      DBDCSV = prevPerl.DBDCSV.overrideAttrs (_: {
        doCheck = false;
      });
    }
  );

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/xxx reaches
  # nixos-unstable
  # inherit (inputs.nixpkgs-xxx.legacyPackages.${final.stdenv.hostPlatform.system}) PKGNAME;

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;
}
