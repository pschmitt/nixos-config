# completions
if [[ -z "$NO_COMPLETIONS" ]]
then
  CUSTOM_COMPS[ps::parent]="kill -0"
  CUSTOM_COMPS[pstree::find]="kill -0"
fi

zsh::autoload-dir ps

alias cmd::restart="ps::restart-app"
