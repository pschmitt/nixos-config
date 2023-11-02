{ lib, fetchFromGitLab, rustPlatform, pkg-config, openssl }:

rustPlatform.buildRustPackage rec {
  pname = "timewarrior-jirapush";
  version = "0.4.1";

  src = fetchFromGitLab {
    owner = "FoxAmes";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-y19qmXXyIV2KUsTNa16gkw7OcqPQy4d1nxFB6WSn8jY=";
  };

  nativeBuildInputs = [ pkg-config openssl ];
  buildInputs = [ openssl ];

  cargoHash = "sha256-jKIrnvDvSxmC1/Lno1LBgR9MQIKHsqF0gpo0dqHa7eI=";

  meta = with lib; {
    description = "A configurable TimeWarrior Extension that uploads timewarrior intervals to Jira as work logs.";
    homepage = "https://gitlab.com/FoxAmes/timewarrior-jirapush";
    license = licenses.mit;
    maintainers = [ maintainers.pschmitt ];
  };
}
