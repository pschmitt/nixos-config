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
    rev = "7f7b21730a605d112ca9f79b6e40105ce7b670ee";
    hash = "sha256-5/DrDLJpOmP9VJubDebj1hnFASfRX4yzuONAeGT7BOM=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "android-skills";
  version = "1.0.24";

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
    jq -er '.skills[] | sub("^\\./"; "")' "${androidSkillsSrc}/.codex-plugin/plugin.json" |
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
