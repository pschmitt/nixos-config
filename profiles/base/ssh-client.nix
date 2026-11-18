{
  config,
  inputs,
  pkgs,
  ...
}:
{
  programs.ssh.knownHosts = import ./ssh-known-hosts.nix {
    inherit inputs;
    inherit (config) domains;
  };

  environment.systemPackages = with pkgs; [
    autossh
    mosh
    sshfs
    sshpass
  ];
}
