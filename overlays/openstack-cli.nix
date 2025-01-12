{ final, prev }:

let
  # TODO bump to 3.12 once it is available
  # https://github.com/NixOS/nixpkgs/pull/363661
  # https://nixpk.gs/pr-tracker.html?pr=363661
  py = prev.python311Packages;
  python-openstackclient = py.python-openstackclient;

  cliPlugins = (python-openstackclient.passthru.optional-dependencies.cli-plugins or [ ]) ++ [
    py.python-octaviaclient
  ];

  openstackclient-full = py.python.withPackages (ps: cliPlugins ++ [ python-openstackclient ]);
in
{
  openstackclient-full = openstackclient-full;
}
