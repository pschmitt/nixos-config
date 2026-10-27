{
  coreutils,
  git,
  just,
  nix,
  nvd,
  writeShellApplication,
}:

writeShellApplication {
  name = "update-and-deploy";
  runtimeInputs = [
    coreutils
    git
    just
    nix
    nvd
  ];
  text = builtins.readFile ../../../scripts/update-and-deploy.sh;
}
