# Terminfo
if (( ! $+commands[infocmp] ))
then
  return
fi

zsh::autoload-dir terminfo
