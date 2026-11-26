# sqlite3
(( $+commands[sqlite3] )) || return

zsh::autoload-dir sqlite

# Alias all sqlite:: functions to sqlite3::
() {
  local func
  for func in ${(kM)functions:#sqlite::*} ${(kM)aliases:#sqlite::*}
  do
    alias ${func//sqlite/sqlite3}="${func}"
  done
}
