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

  wireshark = fixWiresharkHash prev.wireshark;
  wireshark-cli = fixWiresharkHash prev.wireshark-cli;

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/xxx reaches
  # nixos-unstable
  # inherit (inputs.nixpkgs-xxx.legacyPackages.${final.stdenv.hostPlatform.system}) PKGNAME;

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;
}
