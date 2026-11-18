{
  config,
  inputs,
  lib,
  options,
  pkgs,
  ...
}:
{
  programs.ssh.knownHosts = import ./ssh-known-hosts.nix {
    inherit inputs;
    inherit (config) domains;
  };

  environment.systemPackages = [
    pkgs.sshfs
    pkgs.sshpass
  ]
  ++ lib.optionals (!(options ? home-manager)) [
    pkgs.autossh
    pkgs.mosh
  ];
}
