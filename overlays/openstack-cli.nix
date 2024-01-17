{ final, prev }:

{
  openstackclient = prev.openstackclient.overrideAttrs (oldAttrs: {
    propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [ final.python3Packages.designateclient ];
    # As of 2024-01-16 the checks fail (due to py3.11?)
    doCheck = false;
    checkPhase = "";
    doInstallCheck = false;
  });

  python3Packages = prev.python3Packages // {
    designateclient = prev.python3Packages.buildPythonPackage rec {
      pname = "python-designateclient";
      version = "6.0.0";
      # NOTE tests require hacking>=3.0.1,<3.1.0
      # and in nixpks there's only 6.0.1
      # https://github.com/openstack/python-designateclient/blob/master/test-requirements.txt
      doCheck = false;

      src = prev.fetchPypi {
        inherit pname version;
        sha256 = "sha256-Uj67/6h006cQ38mcRuf+9x6NCjWug48kVRL4dQ3FdPQ=";
      };

      propagatedBuildInputs = with prev.python3Packages; [
        pip

        # https://github.com/openstack/python-designateclient/blob/master/requirements.txt
        jsonschema
        osc-lib
        oslo-serialization
        oslo-utils
        pbr
        keystoneauth1
        requests
        stevedore
        debtcollector
      ];

      meta = {
        description = "Python client library for OpenStack Designate DNS service.";
        license = prev.lib.licenses.asl20;
        maintainers = [ prev.maintainers.pschmitt ];
      };
    };
  };
}
