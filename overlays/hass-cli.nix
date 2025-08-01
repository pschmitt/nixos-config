{ final, prev }:
{
  # XXX Remove this overlay once there's a new hass-cli release (> 0.9.6).
  # https://github.com/home-assistant-ecosystem/home-assistant-cli/releases
  home-assistant-cli = prev.home-assistant-cli.overrideAttrs (oldAttrs: {
    version = "0.9.7-dev";

    doCheck = false;
    src = final.fetchFromGitHub {
      owner = "home-assistant-ecosystem";
      repo = "home-assistant-cli";
      rev = "03a6edbc7b9e38d6d6260d3813e6da5e08b45a43";
      hash = "sha256-opuHn7ngSEpUdYkDYzq2QRgkZYfqhG+Uw1DbME6kxwQ=";
    };
    disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_defaults" ];
  });
}
