{
  inputs,
  pkgs,
}:
pkgs.callPackage ./shell-script.nix {
  name = "tmux-slay";
  script = "${inputs.tmux-slay.outPath}/tmux-slay";
  supportFiles = [
    {
      source = "${inputs.tmux-slay.outPath}/completions/_tmux-slay";
      target = "share/zsh/site-functions/_tmux-slay";
    }
  ];
  scriptReplacements = [
    {
      from = "#!/usr/bin/env bash";
      to = "#!/data/data/com.termux/files/usr/bin/bash";
    }
  ];
  aptPackages = [ "gawk" ];
  description = "TMUX script to run commands in a background session";
  homepage = "https://github.com/pschmitt/tmux-slay";
  license = pkgs.lib.licenses.gpl3Only;
}
