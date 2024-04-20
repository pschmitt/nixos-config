{ pkgs, config, ... }: {
  imports = [
    ../common/global

    ../misc/luks-ssh-unlock.nix
    ../misc/git-clone-nixos-config.nix
    ../misc/users/github-actions.nix
    ../misc/users/nix-remote-builder.nix

    ../misc/git-clone-nixos-config.nix
    ../misc/luks-ssh-unlock.nix
    ../misc/users/github-actions.nix
    ../misc/users/nix-remote-builder.nix
  ];

  custom.useBIOS = true;

  # Write logs to console
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  environment.systemPackages = with pkgs; [
    git
  ];
}
