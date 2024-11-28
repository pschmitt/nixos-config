{ final, prev }:

let
  py = prev.python311Packages;
  python-openstackclient = py.python-openstackclient;

  # Attempt to access cli-plugins from passthru (may not always work)
  cliPlugins = (python-openstackclient.passthru.optional-dependencies.cli-plugins or [ ]) ++ [
    py.python-octaviaclient
  ];

  openstackclient-full = py.python.withPackages (ps: cliPlugins ++ [ python-openstackclient ]);
in
{
  openstackclient-full = openstackclient-full;
}
