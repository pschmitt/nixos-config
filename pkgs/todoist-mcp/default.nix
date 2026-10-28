{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "todoist-mcp";
  version = "13.7.1";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = "todoist-mcp";
    rev = "v${version}";
    hash = "sha256-kz6U40a3HboYxkL6IZgTV0W3L7EHT82B9mfE+BesJv0=";
  };

  npmDepsHash = "sha256-TXORm18TWH2Ch71vfKKbPzjZ+azdqElt8BoBZEWpuuw=";

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
