{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "opsgenie-cli";
  version = "0.0.4";

  src = fetchFromGitHub {
    owner = "Skedulo";
    repo = "opsgenie-cli";
    rev = version;
    hash = "sha256-kkhUvFtovUgkUNIz29FrlfWQHq73moFwcxaqQ1XNooY=";
  };

  npmDepsHash = "sha256-CsQoEaKdaicnE/H3V5cYY+FRRMGUa+JOEYXxcHPoYTg=";

  npmBuild = "npm run build";

  # Remove .bin helpers from devDependencies that were pruned away
  postInstall = ''
    rm -rf $out/lib/node_modules/opsgenie/node_modules/.bin
  '';

  meta = with lib; {
    description = "Command-line tool for interacting with Opsgenie";
    homepage = "https://github.com/Skedulo/opsgenie-cli";
    license = licenses.mit;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "opsgenie";
  };
}
