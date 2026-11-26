# yq
if (( ! $+commands[yq] ))
then
  return
fi

# Alias yq:: functions to yaml::
# NOTE This needs to be placed below all yq:: functions!
() {
  local func
  for func in ${(k)functions[(I)yq::*]} ${(k)aliases[(I)yq::*]}
  do
    alias ${func//yq::/yaml::}=${func}
  done
}
