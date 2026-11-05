# Development shells exposed by the flake.

{
  pkgs,
  checks,
}:
{
  default = pkgs.mkShell {
    inherit (checks.pre-commit-check) shellHook;
    buildInputs = checks.pre-commit-check.enabledPackages;

    # Enable experimental features without having to specify the argument
    NIX_CONFIG = "experimental-features = nix-command flakes";
    nativeBuildInputs = with pkgs; [
      # secrets
      age
      ssh-to-age
      sops

      git
      home-manager
      nix

      # lint
      deadnix
      nixfmt
      statix

      # task runner
      just

      opentofu
      yq-go
    ];
  };
}
