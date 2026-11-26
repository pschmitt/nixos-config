# asdf-vm
# Don't return early here, asdf get loaded after local plugins
# if (( ! $+commands[asdf] ))
# then
#   return
# fi

zsh::autoload-dir asdf

alias asdf_update_nvim="asdf_reinstall neovim nightly"
