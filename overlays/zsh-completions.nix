{
  inputs,
  prev,
  ...
}:
let
  date = inputs.zsh-completions.lastModifiedDate;
in
{
  # Track upstream master (flake input) like the yadm shell's zinit does: the
  # 0.36.0 release lacks completions added since (ab, nu, peco, playwright,
  # pwsh, tmuxp, ...).
  zsh-completions = prev.zsh-completions.overrideAttrs (_old: {
    version = "0.36.0-unstable-${builtins.substring 0 4 date}-${builtins.substring 4 2 date}-${builtins.substring 6 2 date}";
    src = inputs.zsh-completions;
  });
}
