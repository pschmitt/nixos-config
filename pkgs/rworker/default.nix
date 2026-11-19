# rworker: client for ad-hoc build workers on OpenStack (talks to the control
# host over SSH, pins each worker's host key locally), its zsh/bash
# completions and an MCP server on top of it (passthru.mcp). The skill that
# tells agents how to use it is home-manager/devel/skills/rworker.
{
  coreutils,
  diffutils,
  gawk,
  gnugrep,
  gnused,
  jq,
  openssh,
  procps,
  python3Packages,
  rsync,
  runCommand,
  symlinkJoin,
  util-linux,
  writeShellApplication,
  writers,
  # Further tools on the client's PATH, ahead of the rest (a wrapped ssh, ...).
  extraRuntimeInputs ? [ ],
  # OpenSSH connection sharing needs a Unix socket; Android's translated
  # app-private paths are too long for one, so TermuxPP turns it off.
  sshControlMaster ? true,
}:
let
  source = builtins.readFile ./rworker.sh;

  client = writeShellApplication {
    name = "rworker";
    # Extras first: a wrapped ssh has to win over openssh's.
    runtimeInputs = extraRuntimeInputs ++ [
      coreutils
      gnused
      jq
      openssh
      procps
      rsync
      util-linux
    ];
    text =
      if sshControlMaster then
        source
      else
        builtins.replaceStrings
          [
            "-o ControlMaster=auto -o ControlPersist=10m"
            ''-o "ControlPath=''${STATE_DIR}/control-%C"''
          ]
          [ "-o ControlMaster=no" "-o ControlPath=none" ]
          source;
  };

  # Home Manager links these into the profile.
  completions = runCommand "rworker-completions" { } ''
    install -Dm644 ${./completions/_rworker} $out/share/zsh/site-functions/_rworker
    install -Dm644 ${./completions/rworker.bash} $out/share/bash-completion/completions/rworker
  '';

  # Ad-hoc build workers as MCP tools (up/ls/exec/start/logs/sync/down), on
  # top of the client so host keys and state are shared.
  mcp = writers.writePython3Bin "rworker-mcp" {
    libraries = [ python3Packages.mcp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./mcp/rworker-mcp.py);
in
symlinkJoin {
  name = "rworker";
  paths = [
    client
    completions
  ];
  # The command spec (read by the completions), the dispatch and the
  # per-action help must list the same actions and flags: a build of the
  # package fails when they drift apart.
  nativeBuildInputs = [
    coreutils
    diffutils
    gawk
    gnugrep
    gnused
  ];
  postBuild = ''
    bash ${./check-spec.sh} ${./rworker.sh}
  '';
  passthru = { inherit mcp; };
  meta = {
    description = "Ad-hoc build workers on OpenStack: client, completions and MCP server";
    mainProgram = "rworker";
  };
}
