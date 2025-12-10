{ config, pkgs, ... }:
{
  users.users.k8s-backdoor = {
    isSystemUser = true;
    description = "Kubernetes Backdoor";
    group = "k8s-backdoor";
    shell = pkgs.bash;
    home = "/var/lib/k8s-backdoor";
    createHome = true;
    openssh.authorizedKeys.keys = config.mainUser.authorizedKeys ++ [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINB37ME2xN0LzQYHToxtTlOCwhaZVlyQ9pfknEusZWuL k8s-backdoor"
    ];
  };

  users.groups.k8s-backdoor = { };

  environment.systemPackages = with pkgs; [
    kubectl
  ];
}
