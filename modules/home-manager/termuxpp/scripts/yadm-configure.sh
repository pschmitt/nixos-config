# Home Manager can activate before yadm-init has cloned the checkout.
if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/yadm/repo.git" ]]
then
  yadm config --replace-all local.class termuxpp '^(termux|termuxpp)$'
fi
