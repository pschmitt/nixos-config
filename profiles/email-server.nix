# Mail server services.
{
  imports = [
    ../services/stalwart.nix
    ../services/roundcube.nix
    ../services/mail-autoconfig.nix
  ];
}
