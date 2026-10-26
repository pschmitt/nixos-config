{ config, lib, ... }:
{
  sops = {
    secrets = {
      "nix/credentials/username" = {
        owner = config.mainUser.username;
      };
      "nix/credentials/password" = {
        owner = config.mainUser.username;
      };
      "nix/github_token" = {
        owner = config.mainUser.username;
      };
      "ssh/nix-remote-builder/privkey" = { };
    };
    templates = {
      nix-cache-netrc.content = lib.concatMapStringsSep "\n" (host: ''
        machine cache.${host}.${config.domains.main}
        login ${config.sops.placeholder."nix/credentials/username"}
        password ${config.sops.placeholder."nix/credentials/password"}
      '') config.nixHost.cacheHosts;
      nix-access-token-github = {
        mode = "0444";
        content = ''
          access-tokens = github.com=${config.sops.placeholder."nix/github_token"}
        '';
      };
    };
  };
}
