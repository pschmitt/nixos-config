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

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    export HOME=$TMPDIR
    $out/bin/td completion install bash
    $out/bin/td completion install zsh
    $out/bin/td completion install fish

    installShellCompletion --cmd td \
      --bash $HOME/.config/tabtab/bash/td.bash \
      --zsh $HOME/.config/tabtab/zsh/td.zsh \
      --fish $HOME/.config/tabtab/fish/td.fish

    substituteInPlace $out/share/bash-completion/completions/td --replace " td completion-server " " $out/bin/td completion-server "
    substituteInPlace $out/share/zsh/site-functions/_td --replace " td completion-server " " $out/bin/td completion-server "
    substituteInPlace $out/share/fish/vendor_completions.d/td.fish --replace " td completion-server " " $out/bin/td completion-server "
  '';

  meta = with lib; {
    description = "Command-line interface for Todoist";
    homepage = "https://github.com/Doist/todoist-cli";
    license = licenses.mit;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "td";
  };
}
