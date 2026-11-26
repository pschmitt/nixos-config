# lm-sensors
if (( ! $+commands[sensors] ))
then
  return
fi

alias temps="sensors::temps"

