{ final, prev }:

let
  py = prev.python311Packages;
  python-openstackclient = py.python-openstackclient;

  # Attempt to access cli-plugins from passthru (may not always work)
  cliPlugins = (python-openstackclient.passthru.optional-dependencies.cli-plugins or [ ]) ++ [
    prev.python311Packages.python-octaviaclient
  ];

  openstackclient-full = py.python.withPackages (
    ps:
    [
      python-openstackclient
    ]
    ++ cliPlugins
  );
in
{
  openstackclient-full = openstackclient-full;
}
