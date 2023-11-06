# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    openstackclientpp = prev.openstackclient.overrideAttrs (oldAttrs: rec {
      propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [ final.python3Packages.designateclient ];
    });

    python3Packages = prev.python3Packages // {
      designateclient = prev.python3Packages.buildPythonPackage rec {
        pname = "python-designateclient";
        version = "5.3.0";

        src = prev.fetchPypi {
          inherit pname version;
          sha256 = "sha256-7nroQeq/8cw4ncRYI4c2btV0o1PEaxapb7QRJT1GmEQ=";
        };

        propagatedBuildInputs = with prev.python3Packages; [
          pbr
          pip
          debtcollector
          requests
          stevedore
          keystoneauth1
          oslo-utils
          oslo-serialization
          osc-lib
          jsonschema
          tzdata
          tempest
          pkgs.reno
          requests-mock
          oslotest
          coverage
          hacking
        ];

        meta = {
          description = "Python client library for OpenStack Designate DNS service.";
          license = prev.lib.licenses.asl20;
          maintainers = [ prev.maintainers.pschmitt ];
        };
      };
    };
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };

    master = import inputs.nixpkgs-master {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}

