if (( ! $+commands[qdbus] )) || [[ "$XDG_SESSION_DESKTOP" != "KDE" ]]
then
  return
fi

alias konsole::toggle="konsole::toggle-background-mode"
alias konsole::show="konsole-background-mode.sh show"
alias konsole::hide="konsole-background-mode.sh hide"
