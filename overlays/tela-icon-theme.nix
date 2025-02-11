{ final, prev }:
{
  # https://github.com/NixOS/nixpkgs/pull/380933
  tela-circle-icon-theme = prev.tela-circle-icon-theme.overrideAttrs (oldAttrs: rec {
    version = "2025-02-10";

    src = prev.fetchFromGitHub {
      owner = "vinceliuice";
      repo = "tela-circle-icon-theme";
      rev = version;
      hash = "sha256-5Kqf6QNM+/JGGp2H3Vcl69Vh1iZYPq3HJxhvSH6k+eQ=";
    };
  });

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

  # https://github.com/NixOS/nixpkgs/pull/380895
  colloid-icon-theme = prev.colloid-icon-theme.overrideAttrs (oldAttrs: rec {
    version = "2025-02-09";

    src = prev.fetchFromGitHub {
      owner = "vinceliuice";
      repo = "colloid-icon-theme";
      rev = version;
      hash = "sha256-x2SSaIkKm1415avO7R6TPkpghM30HmMdjMFUUyPWZsk=";
    };
  });
}
