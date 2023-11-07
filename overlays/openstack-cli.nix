{ final, prev }:

{
  openstackclient-with-designate = prev.openstackclient.overrideAttrs (oldAttrs: rec {
    propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [ final.python3Packages.designateclient ];
  });

  python3Packages = prev.python3Packages // {
    designateclient = prev.python3Packages.buildPythonPackage rec {
      pname = "python-designateclient";
      version = "5.3.0";
      # NOTE tests require hacking>=3.0.1,<3.1.0
      # and in nixpks there's only 6.0.1
      # https://github.com/openstack/python-designateclient/blob/master/test-requirements.txt
      doCheck = false;

      src = prev.fetchPypi {
        inherit pname version;
        sha256 = "sha256-7nroQeq/8cw4ncRYI4c2btV0o1PEaxapb7QRJT1GmEQ=";
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
