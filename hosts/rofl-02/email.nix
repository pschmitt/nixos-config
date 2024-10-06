{ config, ... }:
{

  sops.secrets."email/p@brkn.lol" = {
    sopsFile = config.custom.sopsFile;
  };

  mailserver = {
    enable = true;
    fqdn = "mail.brkn.lol";
    domains = [
      "brkn.lol"
      "heimat.dev"
      "pschmitt.dev"
      # "schmi.tt"
    ];

    # A list of all login accounts. To create the password hashes, use
    # nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'
    loginAccounts = {
      "p@brkn.lol" = {
        hashedPasswordFile = config.sops.secrets."email/p@brkn.lol".path;
        aliases = [ "postmaster@brkn.lol" ];
      };
    };

    # Use Let's Encrypt certificates. Note that this needs to set up a stripped
    # down nginx and opens port 80.
    certificateScheme = "acme-nginx";
  };

  services.roundcube = {
    enable = true;
    configureNginx = true;
    hostName = "webmail.brkn.lol";
    extraConfig = ''
      $config['smtp_server'] = "tls://${config.mailserver.fqdn}";
      $config['smtp_user'] = "%u";
      $config['smtp_pass'] = "%p";
    '';
  };
}
