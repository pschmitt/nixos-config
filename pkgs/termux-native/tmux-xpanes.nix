{
  inputs,
  pkgs,
}:
pkgs.callPackage ./shell-script.nix {
  name = "tmux-xpanes";
  script = "${inputs.tmux-xpanes}/bin/xpanes";
  supportFiles = [
    {
      source = "${inputs.tmux-xpanes}/completion/zsh/_xpanes";
      target = "share/zsh/site-functions/_xpanes";
    }
    {
      source = "${inputs.tmux-xpanes}/man/xpanes.1";
      target = "share/man/man1/xpanes.1";
    }
  ];
  scriptReplacements = [
    {
      from = "#!/usr/bin/env bash";
      to = "#!/data/data/com.termux/files/usr/bin/bash";
    }
    {
      from = "readonly XP_SHELL=\"/usr/bin/env bash\"";
      to = "readonly XP_SHELL=\"/data/data/com.termux/files/usr/bin/bash\"";
    }
  ];
  aptPackages = [ "findutils" ];
  description = "Ultimate terminal divider powered by tmux";
  homepage = "https://github.com/greymd/tmux-xpanes";
  license = pkgs.lib.licenses.mit;
}
