{ final, prev }:

# https://github.com/NixOS/nixpkgs/pull/468021
{
  tmux = prev.tmux.overrideAttrs (oldAttrs: rec {
    # pname = "tmux";
    version = "3.6a";

    src = prev.fetchFromGitHub {
      owner = "tmux";
      repo = "tmux";
      rev = version;
      hash = "sha256-VwOyR9YYhA/uyVRJbspNrKkJWJGYFFktwPnnwnIJ97s=";
    };
  });
}
