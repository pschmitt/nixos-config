# Skill sets maintained upstream, merged next to ./skills for every AI tool
# (home-manager/devel/ai.nix). The skills check in flake.nix derives its
# `--external` names from the same list, so a new entry needs no lint change.
{
  fetchFromGitHub,
  terminal-browser,
  todoist-cli,
}:
let
  rewriteSkills = fetchFromGitHub {
    owner = "rewrite-rs";
    repo = "skills";
    rev = "ae0fd62485d071437ae5e6c4036c986b0dd122a0";
    hash = "sha256-yiARqb8bXkCXAtcJ6umS06Mx0EL8a5q5VZSQiLjMb3w=";
  };

  frontendDesign = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "a7ba5b93db0c7c8d17f3f1d25853adca79598a1a";
    hash = "sha256-C8uTRCtKEvL7dz+dDbfs/DwU/uxH5YzYFDn0oo3BKnA=";
  };

  # https://github.com/czlonkowski/n8n-skills
  n8nSkills = fetchFromGitHub {
    owner = "czlonkowski";
    repo = "n8n-skills";
    rev = "27e9d0ab92cccfc46db4f147497b173f214b69c5";
    hash = "sha256-D8wEZblUGWfXKIxw3TYXhZZ0P4C1lf71cSAVgjOpmes=";
  };
in
[
  "${rewriteSkills}/skills/rust"
  "${rewriteSkills}/skills/porting"
  "${rewriteSkills}/skills/workflow"
  "${rewriteSkills}/skills/misc"
  "${frontendDesign}/plugins/frontend-design/skills"
  "${n8nSkills}/skills"
  "${todoist-cli}/share/skills/todoist-cli"
  "${terminal-browser}/lib/terminal-browser/skills/default"
]
