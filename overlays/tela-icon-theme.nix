{ final, prev }:
{
  # https://github.com/NixOS/nixpkgs/pull/380933
  tela-icon-theme = prev.tela-icon-theme.overrideAttrs (oldAttrs: rec {
    version = "2025-02-10";

    src = prev.fetchFromGitHub {
      owner = "vinceliuice";
      repo = "tela-icon-theme";
      rev = version;
      hash = "sha256-ufjKFlKJnmNwD2m1w+7JSBQij6ltxXWCpUEvVxECS98=";
    };
  });
}
