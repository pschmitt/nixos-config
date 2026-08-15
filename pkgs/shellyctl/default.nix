{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "shellyctl";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "jcodybaker";
    repo = "shellyctl";
    rev = "v${version}";
    hash = "sha256-/KJlv2RDcsWvfGb77a+INqkOhA5+HxZ63ITjVNBnofU=";
  };

  vendorHash = "sha256-eqw6M7aimVTq/V9uPElH7g2gvpVXQ6DfyAM8UGKU2WI=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Unofficial command line client for the Shelly Gen2/3 API";
    homepage = "https://github.com/jcodybaker/shellyctl";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "shellyctl";
  };
}
