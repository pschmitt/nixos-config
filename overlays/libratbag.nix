{ final, prev }: {
  libratbag = prev.libratbag.overrideAttrs (oldAttrs:
    let
      # see https://github.com/libratbag/libratbag/commits/master/
      version = "8444ceb638b19c3fbeb073a5cd29f17c6d34dd07";
    in
    {
      pname = "libratbag";
      version = version;

      src = prev.fetchFromGitHub {
        owner = "libratbag";
        repo = "libratbag";
        rev = version;
        sha256 = "sha256-9rlnGQ7kcXqX+8mFb0imnzLo0X6Nuca6fcMv+H6ZwEw=";
      };
    });
}
