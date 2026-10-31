# Skill sets maintained upstream, merged next to ./skills for every AI tool
# (home-manager/devel/ai.nix). The skills check in flake.nix derives its
# `--external` names from the same list, so a new entry needs no lint change.
{
  fetchFromGitHub,
  terminal-browser,
  todoist-cli,
}:
let
  # https://github.com/czlonkowski/n8n-skills
  n8nSkills = fetchFromGitHub {
    owner = "czlonkowski";
    repo = "n8n-skills";
    rev = "27e9d0ab92cccfc46db4f147497b173f214b69c5";
    hash = "sha256-D8wEZblUGWfXKIxw3TYXhZZ0P4C1lf71cSAVgjOpmes=";
  };
in
[
  "${n8nSkills}/skills"
  "${todoist-cli}/share/skills/todoist-cli"
  "${terminal-browser}/lib/terminal-browser/skills/default"
]
