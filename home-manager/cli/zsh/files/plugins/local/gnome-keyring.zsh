# gnome-keyring
if (( ! $+commands[gnome-keyring-daemon] ))
then
  return
fi

# Alias gnome-keyring:: functions to gkr::
() {
  local func
  for func in ${(k)functions[(I)gnome-keyring::*]}
  do
    alias ${func//gnome-keyring/gcr}=${func}
    alias ${func//gnome-keyring/gkr}=${func}
  done
}
