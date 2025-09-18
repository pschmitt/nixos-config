{ config, pkgs, ... }:
{

  sops.secrets."github-runners/nixos-config/token" = {
    sopsFile = config.custom.sopsFile;
  };

  services.github-runners.nixos-config = {
    enable = true;

    name = config.networking.hostName;
    replace = true;
    ephemeral = false;

    # Run the runner as our dedicated user so $HOME is writable
    user = "github-actions";
    group = "github-actions";

    url = "https://github.com/pschmitt/nixos-config";
    tokenFile = config.sops.secrets."github-runners/nixos-config/token".path;

    noDefaultLabels = false;
    extraLabels = [
      "linux"
      "nixos"
      "self-hosted"
    ];

    extraPackages = with pkgs; [
      coreutils
      git
      gnugrep
      jq
      nix
      openssh
      xz
    ];

    # Keep the runner work directory under the user's home
    # workDir = "/var/lib/github-actions/_work";

    # Ensure HOME points to the user's home (the upstream unit may default to /run)
    # serviceOverrides.Environment = [ "HOME=/var/lib/github-actions" ];
  };

  # Make sure the SSH directory exists and is owned correctly, so the workflow
  # can write the private key to ${HOME}/.ssh/id_ed25519 without permission issues.
  # systemd.tmpfiles.rules = [
  #   "d /var/lib/github-actions/.ssh 0700 github-actions github-actions -"
  # ];
}
