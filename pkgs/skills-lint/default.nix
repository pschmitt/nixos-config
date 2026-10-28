{ writers }:

# Repo-specific checks for agent skills on top of the Agent Skills spec
# (skills-ref): SKILL.md length, links, unreferenced references/ files,
# unknown skill names and script permissions. Used by the `skills` flake check.
writers.writePython3Bin "skills-lint" {
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./scripts/skills-lint.py)
