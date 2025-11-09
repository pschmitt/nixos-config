{
  lib,
  ...
}:
{
  imports = [
    ./dotfiles/bash.nix
    ./dotfiles/starship.nix
    ./dotfiles/zsh.nix
  ];

  environment = {
    enableAllTerminfo = true;
  };

  programs = {
    gnupg.agent.enableSSHSupport = lib.mkForce false;
    ssh.startAgent = true;
  };
}
