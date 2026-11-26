{ pkgs, ... }:
{
  # LDIF -> JSON for the ldap:: functions.
  home.packages = [ pkgs.ldif2json ];
}
