{
  lib,
  fetchFromGitLab,
  rustPlatform,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "timewarrior-jirapush";
  version = "0.6.0";

  src = fetchFromGitLab {
    owner = "FoxAmes";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-mQH3w3ke6biaJuVPQ7aDSo1BxN1kGvQDl5cz3aYFErk=";
  };

  nativeBuildInputs = [
    pkg-config
    openssl
  ];
  buildInputs = [ openssl ];

  cargoHash = "sha256-8HQPeaH/wWIBZvu/hmgwduXaFfLHXzVzfAFXW9844AY=";

  meta = {
    description = "A configurable TimeWarrior Extension that uploads timewarrior intervals to Jira as work logs.";
    homepage = "https://gitlab.com/FoxAmes/timewarrior-jirapush";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "jirapush";
  };
}
