# Wireshark/tshark
if (( ! $+commands[wireshark] )) && (( ! $+commands[tshark] ))
then
  return
fi

zsh::autoload-dir wireshark
