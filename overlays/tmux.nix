{ final, prev }:

{
  tmux = prev.tmux.overrideAttrs (oldAttrs: {
    pname = "tmux";
    version = "9ae69c3";

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
      rev = "9ae69c3795ab5ef6b4d760f6398cd9281151f632";
      sha256 = "sha256-RX3RZ0Mcyda7C7im1r4QgUxTnp95nfpGgQ2HRxr0s64=";
    };
  });
}
