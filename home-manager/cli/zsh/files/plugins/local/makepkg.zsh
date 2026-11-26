# makepkg (Arch Linux)
if (( ! $+commands[makepkg] ))
then
  return
fi

zsh::autoload-dir makepkg
