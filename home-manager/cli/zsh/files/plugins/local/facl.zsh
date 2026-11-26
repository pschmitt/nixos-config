# Filesystem ACL wrappers
if (( ! $+commands[getfacl] ))
then
  return
fi

zsh::autoload-dir facl
