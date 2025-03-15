{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "cdpcurl";
  version = "0.0.6";

  src = fetchFromGitHub {
    owner = "coinbase";
    repo = "cdpcurl";
    rev = "v${version}";
    hash = "sha256-qzvl9Ra8nA3hzqkMoiakq4NsJnB1uc6lV0hJ5kPa85Q=";
  };

  vendorHash = "sha256-wTr4TglKpMHWFz4SgHH1UwqQ4d5ThphShGce1ZW1oMw=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "";
    homepage = "https://github.com/coinbase/cdpcurl";
    # NOTE There is no license file in the repository as of 2025-03-15
    # https://github.com/coinbase/cdpcurl/issues/39
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "cdpcurl";
  };
}
