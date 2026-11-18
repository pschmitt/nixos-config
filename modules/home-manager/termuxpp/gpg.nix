{ config, ... }:
{
  home.sessionVariables.GNUPGHOME = "${config.xdg.configHome}/gnupg";
  xdg.configFile."gnupg/gpg-agent.conf" = {
    # Replace the former yadm alternate on existing phones.
    force = true;
    text = ''
      allow-loopback-pinentry
      max-cache-ttl 28800
      default-cache-ttl 28800
      enable-ssh-support
      default-cache-ttl-ssh 28800
      max-cache-ttl-ssh 28800
    '';
  };
}
