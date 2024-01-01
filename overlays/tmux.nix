{ final, prev }:

{
  tmux = prev.tmux.overrideAttrs (oldAttrs: {
    pname = "tmux-git";
    version = "4266d3";

    patches = [ ];

    configureFlags = [
      "--sysconfdir=/etc"
      "--localstatedir=/var"
      "--enable-systemd"
      "--enable-utempter"
      "--enable-utf8proc"
      "--enable-sixel"
    ];

    src = prev.fetchFromGitHub {
      owner = "tmux";
      repo = "tmux";
      rev = "4266d3efc89cdf7d1af907677361caa24b58c9eb";
      sha256 = "sha256-LliON7p1KyVucCu61sPKihYxtXsAKCvAvRBvNgoV0/g=";
    };
  });
}
