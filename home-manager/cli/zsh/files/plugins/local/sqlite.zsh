# sqlite3
(( $+commands[sqlite3] )) || return

# Alias all sqlite:: functions to sqlite3::
() {
  local func
  for func in ${(k)functions[(I)sqlite::*]} ${(k)aliases[(I)sqlite::*]}
  do
    alias ${func//sqlite/sqlite3}="${func}"
  done
}
