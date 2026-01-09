# Shell for bootstrapping flake-enabled nix and home-manager
# You can enter it through 'nix develop' or (legacy) 'nix-shell'

{
  pkgs ? (import ./nixpkgs.nix) { },
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
      nixfmt
      statix

      # task runner
      just

      opentofu
      yq-go
    ];
  };
}
