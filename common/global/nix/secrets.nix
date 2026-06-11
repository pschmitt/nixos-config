{ config, ... }:
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
      nix-cache-netrc.content = ''
        machine cache.rofl-10.brkn.lol
        login ${config.sops.placeholder."nix/credentials/username"}
        password ${config.sops.placeholder."nix/credentials/password"}

        machine cache.rofl-13.brkn.lol
        login ${config.sops.placeholder."nix/credentials/username"}
        password ${config.sops.placeholder."nix/credentials/password"}

        machine cache.rofl-14.brkn.lol
        login ${config.sops.placeholder."nix/credentials/username"}
        password ${config.sops.placeholder."nix/credentials/password"}
      '';
      nix-access-token-github.content = ''
        access-tokens = github.com=${config.sops.placeholder."nix/github_token"}
      '';
    };
  };
}
