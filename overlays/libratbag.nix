# TODO remove this overlay once this is merged:
# https://github.com/NixOS/nixpkgs/pull/345782
{ final, prev }:
{
  libratbag = prev.libratbag.overrideAttrs (
    oldAttrs:
    let
      # see https://github.com/libratbag/libratbag/commits/master/
      version = "v0.18";
    in
    {
      pname = "libratbag";
      version = version;

      src = prev.fetchFromGitHub {
        owner = "libratbag";
        repo = "libratbag";
        rev = version;
        hash = "sha256-dAWKDF5hegvKhUZ4JW2J/P9uSs4xNrZLNinhAff6NSc=";
      };
    }
  );

  piper = prev.piper.overrideAttrs (
    oldAttrs:
    let
      # see https://github.com/libratbag/piper/commits/master/
      version = "0.8";
    in
    {
      pname = "piper";
      version = version;

      mesonFlags = [ "-Druntime-dependency-checks=false" ];

      src = prev.fetchFromGitHub {
        owner = "libratbag";
        repo = "piper";
        rev = version;
        sha256 = "sha256-j58fL6jJAzeagy5/1FmygUhdBm+PAlIkw22Rl/fLff4=";
      };
    }
  );
}
