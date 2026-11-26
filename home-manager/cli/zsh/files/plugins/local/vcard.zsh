
() {
  local func
  for func in ${(k)functions[(I)vcard::*]} ${(k)aliases[(I)vcard::*]}
  do
    alias ${func//vcard::/vcf::}=${func}
  done
}
