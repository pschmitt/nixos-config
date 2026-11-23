# tmux plugins, formerly installed by tpm: from nixpkgs where packaged, our
# forks pinned. Loaded in the order of the old @tpm_plugins list and named
# after tpm's checkout directories, since scripts look them up in
# $TMUX_PLUGIN_MANAGER_PATH (~/.local/share/tpm).
# Disabled before the move: noscript/tmux-mighty-scroll
{ pkgs }:
let
  inherit (pkgs) fetchFromGitHub;
  inherit (pkgs.tmuxPlugins) mkTmuxPlugin;

  pinned =
    {
      owner,
      repo,
      rev,
      hash,
      date,
      ...
    }@args:
    mkTmuxPlugin {
      pluginName = repo;
      version = "0-unstable-${date}";
      inherit (args) rtpFilePath;
      src = fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };
    };
in
[
  {
    name = "tmux-thumbs";
    plugin = pkgs.tmuxPlugins.tmux-thumbs;
  }
  {
    name = "extrakto";
    plugin = pkgs.tmuxPlugins.extrakto;
  }
  {
    name = "tmux-zsh-vim-titles";
    plugin = pinned {
      owner = "MikeDacre";
      repo = "tmux-zsh-vim-titles";
      rev = "3c2564ff62636aea69e0de9d268954db86e1098f";
      hash = "sha256-awIKc8u04sBKcY5svOkt5uvK4dFWj6G3uMYPjlBJ2I8=";
      date = "2023-09-05";
      rtpFilePath = "unified-titles.tmux";
    };
  }
  {
    name = "tmux-battery";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-battery";
      rev = "2e85180753241e5b6756a424980ba6181730783b";
      hash = "sha256-5UqwGzJA8mTeyFKL7/RBP7Xba2zXOJKmGiF6v0R9poI=";
      date = "2026-09-06";
      rtpFilePath = "battery.tmux";
    };
  }
  {
    name = "tmux-cpu";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-cpu";
      rev = "97321b0a9925068664546d28076f879f988b11ce";
      hash = "sha256-XC+Le+IqPlemEHTdJhbGmk1TrOUkA/vOBPsdrxontys=";
      date = "2026-09-06";
      rtpFilePath = "cpu.tmux";
    };
  }
  {
    name = "tmux-forsaken";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-forsaken";
      rev = "c2439c6166b7e94a150a878e1c7ecda1e9b59328";
      hash = "sha256-CpHddPBgWrTG85JqGh/pqdNhjivRtlx/ncPDgJtB2Wo=";
      date = "2023-12-12";
      rtpFilePath = "forsaken.tmux";
    };
  }
  {
    name = "tmux-pain-control";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-pain-control";
      rev = "101c27d8b78bed3f933db83488a24035f574e19c";
      hash = "sha256-6+lErKB/c68qJHsZBFu3gpNGbyzZgoq9Tby7NryJd2g=";
      date = "2020-05-30";
      rtpFilePath = "pain_control.tmux";
    };
  }
  {
    name = "tmux-rerespawn";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-rerespawn";
      rev = "6942adc8dac2928751816f595268838697f07dbb";
      hash = "sha256-vtVzlaYhPobJTw6Ec7c1fPqFFXG1FRqzEgUQpvrowNw=";
      date = "2021-04-12";
      rtpFilePath = "rerespawn.tmux";
    };
  }
  {
    name = "tmux-ssh-split";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-ssh-split";
      rev = "338bc3254be2749216d3d2f76a3314af9f7da815";
      hash = "sha256-F9UtG0sLL437BCGFMmdrVKeGkmHWDnasJa5/GBPOMKs=";
      date = "2026-09-17";
      rtpFilePath = "ssh-split.tmux";
    };
  }
  {
    name = "tmux-weather";
    plugin = pinned {
      owner = "pschmitt";
      repo = "tmux-weather";
      rev = "f3668cc11aa312023bc6fd69423c21e6d258a3b8";
      hash = "sha256-pQrY207OL5ux1FMk+POxknDKmpJP1uBtVoN2KxSYFLg=";
      date = "2021-04-26";
      rtpFilePath = "tmux-weather.tmux";
    };
  }
  {
    name = "tmux-fuzzback";
    plugin = pkgs.tmuxPlugins.fuzzback;
  }
  {
    name = "tmux-prefix-highlight";
    plugin = pkgs.tmuxPlugins.prefix-highlight;
  }
  {
    name = "tmux-sensible";
    plugin = pkgs.tmuxPlugins.sensible;
  }
  {
    name = "tmux-drag";
    plugin = pinned {
      owner = "kilofox";
      repo = "tmux-drag";
      rev = "7853d519c26612748f2ed9673d3c13bafb923712";
      hash = "sha256-AR1RVujj1Q5Ixx6It9a7dbOvwrS5LkVgbsxYsbRSwv8=";
      date = "2026-09-22";
      rtpFilePath = "tmux_drag.tmux";
    };
  }
]
