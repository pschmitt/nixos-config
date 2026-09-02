# Forgejo Actions runner (act_runner), registering against the forgejo
# instance on rofl-10. Runs on compute nodes rather than the git server
# itself so CI/build jobs don't compete with forgejo for resources.
{ config, ... }:
{
  sops.secrets."forgejo/runner/token" = config.custom.mkSecret { };

  # act_runner reads its registration token from an EnvironmentFile, which
  # systemd loads as root before dropping to the runner's DynamicUser -- so
  # the secret file itself never needs to be readable by that user.
  sops.templates."forgejo-runner-token".content = ''
    TOKEN=${config.sops.placeholder."forgejo/runner/token"}
  '';

  services.gitea-actions-runner.instances.main = {
    enable = true;
    name = config.networking.hostName;
    url = "https://git.${config.domains.main}";
    tokenFile = config.sops.templates."forgejo-runner-token".path;
    labels = [
      "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest"
      "ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
      "${config.networking.hostName}:docker://ghcr.io/catthehacker/ubuntu:act-latest"
    ];
  };
}
