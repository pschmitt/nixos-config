{ config, lib, ... }:
let
  # Readers of the GitHub access token below (Nix fetching private flake
  # inputs as a non-root user). Services that need it join this group; it
  # used to be world-readable.
  tokenGroup = "nix-access-tokens";
in
{
  users = {
    groups.${tokenGroup} = { };
    users.${config.mainUser.username}.extraGroups = [ tokenGroup ];
  };

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
      # An unreadable !include is skipped silently by Nix (configuration.cc
      # catches the SystemError), so users outside the group just get no token.
      nix-access-token-github = {
        mode = "0440";
        group = tokenGroup;
        content = ''
          access-tokens = github.com=${config.sops.placeholder."nix/github_token"}
        '';
      };
    };
  };
}
