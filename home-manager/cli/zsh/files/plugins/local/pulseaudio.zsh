# Generic PulseAudio wrapper commands
if (( ! $+commands[pactl] ))
then
  return
fi

alias mute="pulseaudio::mute-all"
# alias unmute="pulseaudio::set-mute-sources-all; pulseaudio::set-mute-sinks-all"
alias unmute="pulseaudio::unmute-default"
alias umute="unmute"
