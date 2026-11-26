zsh::autoload-dir vcard

() {
  local func
  for func in ${(kM)functions:#vcard::*} ${(kM)aliases:#vcard::*}
  do
    alias ${func//vcard::/vcf::}=${func}
  done
}
