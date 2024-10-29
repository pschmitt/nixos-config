{
  lib,
  python3,
  fetchgit,
}:

python3.pkgs.buildPythonApplication {
  pname = "emoji-fzf";
  version = "0.9.0";
  pyproject = true;

  # NOTE The build fails missing data when using fetchFromPypi
  # and fetchFromGitHub does not seem to clone recursively, even
  # with fetchSubmodules=true
  src = fetchgit {
    url = "https://github.com/noahp/emoji-fzf.git";
    # NOTE This commit is the latest as of 2024-10-29
    # Sadly there is no 0.9.0 tag yet.
    rev = "d79dd3c9a91ccc387907f83193e435ff623754d4";
    sha256 = "sha256-e9ywYhb1C1i6Epgp3G9Dxa7Q4trjkMC0KOX+F6ncgb4=";
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
