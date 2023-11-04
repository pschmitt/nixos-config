{ lib, fetchFromGitHub, python3 }:

python3.pkgs.buildPythonApplication rec {
  version = "1.4.2";
  pname = "brotab";

  src = fetchFromGitHub {
    owner = "balta2ar";
    repo = pname;
    rev = version;
    hash = "sha256-HKKjiW++FwjdorqquSCIdi1InE6KbMbFKZFYHBxzg8Q=";
  };

  propagatedBuildInputs = with python3.pkgs; [
    pip
    requests
    flask
    psutil
    setuptools
  ];

  postPatch = ''
    substituteInPlace requirements/base.txt \
      --replace "Flask==2.0.2" "Flask>=2.0.2" \
      --replace "psutil==5.8.0" "psutil>=5.8.0" \
      --replace "requests==2.24.0" "requests>=2.24.0"
  '';

  postInstall = ''
    mkdir -p $out/lib/mozilla/native-messaging-hosts
    sed -r "s#(\"path\":).*#\1 \"$out/bin/bt_mediator\",#" $out/lib/python3*/site-packages/brotab/mediator/firefox_mediator.json > $out/lib/mozilla/native-messaging-hosts/brotab_mediator.json
  '';

  nativeCheckInputs = with python3.pkgs; [
    pytestCheckHook
  ];

  meta = with lib; {
    homepage = "https://github.com/balta2ar/brotab";
    description = "Control your browser's tabs from the command line";
    license = licenses.mit;
    maintainers = with maintainers; [ doronbehar ];
  };
}
