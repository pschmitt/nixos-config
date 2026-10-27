{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "todoist-mcp";
  version = "13.7.0";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = "todoist-mcp";
    rev = "v${version}";
    hash = "sha256-zdg7oyyqvPso8flMnLI1vnPWvf16p7qvBCVPHLYXVYY=";
  };

  npmDepsHash = "sha256-a/Kp68TSnf88qxeZtQecDRXsR04C9B3g3QMl2Ch/mt4=";

  doCheck = false;

  # Under qemu-user aarch64 emulation (cross builds on x86_64), Node's V8 JIT
  # hits a known QEMU TCG translation cache threading race causing SIGILL
  # (signal 4: Illegal instruction). Running with --jitless forces bytecode
  # interpretation, preventing dynamic code generation races in QEMU.
  env.NODE_OPTIONS = lib.optionalString stdenv.hostPlatform.isAarch64 "--jitless";

  passthru.updatePolicy.autoMerge = "patch";

  meta = {
    description = "Model Context Protocol (MCP) server for Todoist";
    homepage = "https://github.com/Doist/todoist-mcp";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "todoist-mcp";
  };
}
