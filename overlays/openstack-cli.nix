{ final, prev }:

let
  # TODO bump to 3.12 once it is available
  # https://github.com/NixOS/nixpkgs/pull/363661
  # https://nixpk.gs/pr-tracker.html?pr=363661
  py = prev.python311Packages;
  python-openstackclient = py.python-openstackclient;

  cliPlugins = (python-openstackclient.passthru.optional-dependencies.cli-plugins or [ ]) ++ [
    # FIX build error:
    # > Finished creating a wheel...
    # > Finished executing pypaBuildPhase
    # > Running phase: pythonRuntimeDepsCheckHook
    # > Executing pythonRuntimeDepsCheck
    # > Checking runtime dependencies for python_octaviaclient-3.8.0-py3-none-any.whl
    # >   - python-neutronclient not installed
    py.python-neutronclient
    py.python-octaviaclient
  ];

  openstackclient-full = py.python.withPackages (ps: cliPlugins ++ [ python-openstackclient ]);
in
{
  openstackclient-full = openstackclient-full;
}
