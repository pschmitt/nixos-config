{ final, prev }:

{
  tmux = prev.tmux.overrideAttrs (oldAttrs: {
    # pname = "tmux";
    version = "3.5a-unreleased";

    src = prev.fetchFromGitHub {
      owner = "tmux";
      repo = "tmux";
      rev = "356887bca27b48e895eca261e0989319f432de73";
      hash = "sha256-sF1Ccs/7grn7qFx7Xwh8HlwgD0UQSMNn7mtMe9syj1I=";
    };
  });
}
