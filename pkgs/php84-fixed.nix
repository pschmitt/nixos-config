{ pkgs }:
pkgs.callPackage (pkgs.path + "/pkgs/development/interpreters/php/generic.nix") {
  version = "8.4.27";
  phpSrc = pkgs.fetchurl {
    url = "https://www.php.net/distributions/php-8.4.27.tar.xz";
    hash = "sha256-3Pk5I7Djjg1SUrJbeWUgtaR3YaCLNIi20LXREVdk0/A=";
  };
  # Keep the PHP filter tests enabled; the upstream nixpkgs PR fixes their
  # invocation for this release's test behavior.
  packageOverrides = _final: prev: {
    extensions = prev.extensions // {
      filter = prev.extensions.filter.overrideAttrs (_old: {
        postConfigure = ''
          substituteInPlace \
            tests/oom_filter_input.phpt \
            tests/oom_filter_input_array.phpt \
            tests/oom_filter_default_encoded.phpt \
            --replace-fail "'-n'," "'-n', '-d', 'extension=$PWD/modules/filter.so',"
        '';
      });
    };
  };
}
