{ final, prev }:

{
  tmux = prev.tmux.overrideAttrs (oldAttrs: {
    pname = "tmux-git";
    version = "bdf8e61";

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
      rev = "bdf8e614af34ba1eaa8243d3a818c8546cb21812";
      sha256 = "sha256-ZMlpSOmZTykJPR/eqeJ1wr1sCvgj6UwfAXdpavy4hvQ=";
    };
  });
}
