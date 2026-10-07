{ pkgs, ... }:
{
  # LDIF -> JSON for the ldap:: functions. zinit hosts get the script from
  # yadm's ~/bin instead.
  home.packages = [ pkgs.ldif2json ];
}
