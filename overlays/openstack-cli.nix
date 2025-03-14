{ final, prev }:

let
  py = prev.python312Packages;
  python-openstackclient = py.python-openstackclient;

  # cliPlugins = (python-openstackclient.passthru.optional-dependencies.cli-plugins or [ ]) ++ [
  #   py.python-octaviaclient
  # ];

  # FIXME ironicclient is not building as of 2025-03-14 (special thanks to @kbudde!)
  cliPlugins = builtins.filter (p: p != py.python-ironicclient) (
    (python-openstackclient.passthru.optional-dependencies.cli-plugins or [ ])
    ++ [
      py.python-octaviaclient
    ]
  );

  openstackclient-full = py.python.withPackages (ps: cliPlugins ++ [ python-openstackclient ]);
in
{
  openstackclient-full = openstackclient-full;
}
