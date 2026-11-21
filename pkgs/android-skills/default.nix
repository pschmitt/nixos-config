{
  fetchFromGitHub,
  installAgentSkills,
  jq,
  lib,
  stdenvNoCC,
}:

let
  androidSkillsSrc = fetchFromGitHub {
    owner = "android";
    repo = "skills";
    rev = "c72942584fff970dac86ced78b367fce0c441e52";
    hash = "sha256-Syj3TJoQkTbWncuKyIzmQfQL2jhwcBo/DHHdHCbivaY=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "android-skills";
  version = "1.0.23";

  src = androidSkillsSrc;

  nativeBuildInputs = [
    installAgentSkills
    jq
  ];

  dontConfigure = true;
  dontBuild = true;
  dontInstallAgentSkills = true;

  postInstall = ''
    set -o pipefail
    jq -er '.skills[] | sub("^\./"; "")' "${androidSkillsSrc}/.codex-plugin/plugin.json" |
      while IFS= read -r skill
      do
        installSkill "${androidSkillsSrc}/$skill"
      done
  '';

  meta = {
    description = "Official Android agent skills";
    homepage = "https://github.com/android/skills";
    license = lib.licenses.asl20;
  };
}
