{
  lib,
  python3,
  fetchPypi,
}:

let
  version = "0.12.0";
in

python3.pkgs.buildPythonApplication {
  pname = "emoji-fzf";
  inherit version;
  pyproject = true;

  src = fetchPypi {
    pname = "emoji_fzf";
    inherit version;
    sha256 = "sha256-E0GquaRS0joI/vWx5SIU1Wu6YGI8nU9ZWg4FvLxLEPU=";
  };

  build-system = [ python3.pkgs.hatchling ];

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
