{
  lib,
  python3,
  fetchgit,
}:

let
  version = "0.10.0";
in

python3.pkgs.buildPythonApplication {
  pname = "emoji-fzf";
  inherit version;
  pyproject = true;

  # NOTE The build fails missing data when using fetchFromPypi
  # and fetchFromGitHub does not seem to clone recursively, even
  # with fetchSubmodules=true
  src = fetchgit {
    url = "https://github.com/noahp/emoji-fzf.git";
    rev = version;
    sha256 = "sha256-W1lCzV+RjhjjbD2sHPQayGB7iu9eIcvy7EPrxFkORv4=";
    fetchSubmodules = true;
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
    python3.pkgs.twine
  ];

  dependencies = with python3.pkgs; [ click ];

  pythonImportsCheck = [ "emoji_fzf" ];

  meta = {
    description = "Emoji searcher for use with fzf";
    homepage = "https://github.com/noahp/emoji-fzf";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "emoji-fzf";
  };
}
