# inotify
if (( ! $+commands[inotifywait] ))
then
  return
fi

zsh::autoload-dir inotify
