{
  lib,
  python3,
  fetchPypi,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "immich-face-to-album";
  version = "1.0.6";
  pyproject = true;

  src = fetchPypi {
    pname = "immich_face_to_album";
    inherit version;
    hash = "sha256-BBUQTq+hzTQNY1kjhMdHdH+X4v3rp1QX6o7+WiRwXBk=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
  ];

  dependencies = with python3.pkgs; [
    click
    requests
  ];

  pythonImportsCheck = [ "immich_face_to_album" ];

  meta = {
    description = "Tool to import a user's face from Immich into an album, mimicking the Google Photos \"auto-updating album\" feature";
    homepage = "https://pypi.org/project/immich-face-to-album/";
    license = lib.licenses.wtfpl;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "immich-face-to-album";
  };
}
