{ final, prev }: {
  piper = prev.piper.overrideAttrs (oldAttrs:
    let
      # see https://github.com/libratbag/piper/commits/master/
      version = "66c1897540d107e48227ce05c5ac51ea41454feb";
    in
    {
      pname = "piper";
      version = version;

      mesonFlags = [
        "-Druntime-dependency-checks=false"
      ];

      src = prev.fetchFromGitHub {
        owner = "libratbag";
        repo = "piper";
        rev = version;
        sha256 = "sha256-ar1f0d2dzgUCL9F/AI1la26i/4Ab6SgxmeTjiI1J4z0=";
      };
    });
}
