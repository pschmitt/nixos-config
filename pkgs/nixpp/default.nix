{
  lib,
  stdenv,
  buildPackages,
  dix,
  installShellFiles,
  rustPlatform,
  python3,
}:
let
  completionGenerator =
    if stdenv.buildPlatform.canExecute stdenv.hostPlatform then
      "$out/bin/nixpp"
    else
      lib.getExe (buildPackages.callPackage ./default.nix { });
in
rustPlatform.buildRustPackage {
  pname = "nixpp";
  version = "0.5.0";
  src = lib.cleanSource ./source;
  cargoLock.lockFile = ./source/Cargo.lock;
  nativeBuildInputs = [ installShellFiles ];
  postInstall = ''
    "${completionGenerator}" completions bash > nixpp
    "${completionGenerator}" completions zsh > _nixpp
    "${completionGenerator}" completions fish > nixpp.fish
    installShellCompletion --cmd nixpp --bash nixpp --zsh _nixpp --fish nixpp.fish
  '';
  NIXPP_REFERENCE_PREPARE = ./tests/prepare-session.py;
  NIXPP_REFERENCE_PYTHON = "${python3}/bin/python3";
  NIXPP_DIX = lib.getExe dix;

  meta = {
    description = "Declarative Android guest system manager";
    mainProgram = "nixpp";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
