# Nix port of the yadm ~/bin/fzf-preview (fzf --preview helper: files with
# bat, images with kitty/chafa, directories with eza/tree).
{
  lib,
  bat,
  chafa,
  eza,
  file,
  tree,
  writeShellApplication,
}:
writeShellApplication {
  name = "fzf-preview";
  runtimeInputs = [
    bat
    chafa
    eza
    file
    tree
  ];
  # The script probes optional tools and unset terminal variables.
  bashOptions = [ ];
  text = builtins.readFile ./fzf-preview.sh;
  meta = {
    description = "fzf preview helper for files, images and directories";
    platforms = lib.platforms.unix;
    mainProgram = "fzf-preview";
  };
}
