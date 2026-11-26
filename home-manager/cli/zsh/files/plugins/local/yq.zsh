# yq
if (( ! $+commands[yq] ))
then
  return
fi

zsh::autoload-dir yq

# Alias yq:: functions to yaml::
# NOTE This needs to be placed below all yq:: functions!
() {
  local func
  for func in ${(kM)functions:#yq::*} ${(kM)aliases:#yq::*}
  do
    alias ${func//yq::/yaml::}=${func}
  done
}
