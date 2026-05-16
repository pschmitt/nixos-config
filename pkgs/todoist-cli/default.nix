{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  installShellFiles,
}:

buildNpmPackage rec {
  pname = "todoist-cli";
  version = "1.64.0";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-mTN6Ep5D4GEEiv5SFDSesZzpYI8Cbem9bZzp+00YOis=";
  };

  npmDepsHash = "sha256-gpTowutDoyY7TnVk5QIVp1igZhjGbQK6qcUczcRb3TA=";

  doCheck = false;

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    tabtabTemplates=$out/lib/node_modules/@doist/todoist-cli/node_modules/@pnpm/tabtab/lib/templates

    mkdir -p "$TMPDIR/completions"
    sed "s/{pkgname}/td/g; s|{completer}|$out/bin/td|g" \
      "$tabtabTemplates/completion.bash" > "$TMPDIR/completions/td.bash"
    sed "s/{pkgname}/td/g; s|{completer}|$out/bin/td|g" \
      "$tabtabTemplates/completion.zsh" > "$TMPDIR/completions/_td"
    sed "s/{pkgname}/td/g; s|{completer}|$out/bin/td|g" \
      "$tabtabTemplates/completion.fish" > "$TMPDIR/completions/td.fish"

    installShellCompletion --cmd td \
      --bash "$TMPDIR/completions/td.bash" \
      --zsh "$TMPDIR/completions/_td" \
      --fish "$TMPDIR/completions/td.fish"
  '';

  meta = with lib; {
    description = "Command-line interface for Todoist";
    homepage = "https://github.com/Doist/todoist-cli";
    license = licenses.mit;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "td";
  };
}
