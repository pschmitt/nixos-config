{
  final,
  # inputs,
  prev,
  ...
}:

{
  # FIX For google-chrome crashing on Hyprland when moving the window from
  # one monitor to another.
  # https://github.com/hyprwm/Hyprland/discussions/11843
  google-chrome = prev.google-chrome.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/google-chrome-stable \
        --add-flags "--disable-features=WaylandWpColorManagerV1"
    '';
  });

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
  inherit (final.python313Packages) parsedmarc;

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/xxx reaches
  # nixos-unstable
  # inherit (inputs.nixpkgs-xxx.legacyPackages.${final.stdenv.hostPlatform.system}) PKGNAME;

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;
}
