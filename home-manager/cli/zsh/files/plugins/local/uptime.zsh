# Uptime
if (( ! $+commands[uptime] ))
then
  return
fi

zsh::autoload-dir uptime
