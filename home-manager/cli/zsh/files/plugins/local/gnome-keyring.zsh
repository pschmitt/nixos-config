# gnome-keyring
if (( ! $+commands[gnome-keyring-daemon] ))
then
  return
fi

zsh::autoload-dir gnome-keyring

# Alias gnome-keyring:: functions to gkr::
() {
  local func
  for func in ${(kM)functions:#gnome-keyring::*}
  do
    alias ${func//gnome-keyring/gcr}=${func}
    alias ${func//gnome-keyring/gkr}=${func}
  done
}
