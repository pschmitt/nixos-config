{ pkgs, ... }:
{
  imports = [
    ./dotfiles/neovim.nix
    ./dotfiles/tmux.nix
  ];

  environment = {
    variables = {
      FZF_DEFAULT_OPTS = "--ansi --history $HOME/.local/share/fzf_history --height 100% --info=inline";
    };

    shells = with pkgs; [ zsh ];
    # Make ZSH respect XDG
    etc = {
      "zshenv.local" = {
        text = ''
          export ZDOTDIR="$HOME/.config/zsh"
        '';
        mode = "0644";
      };
    };
    systemPackages = with pkgs; [
      (vim-full.customize {
        name = "vim";
        vimrcConfig.customRC = ''
          set nocompatible
          filetype plugin indent on
          syntax on
          set modeline
          set autoindent expandtab smarttab
          set mouse=a
          scriptencoding utf-8
          set backspace=indent,eol,start
        '';
      })
    ];
  };

  programs = {
    fzf = {
      keybindings = true;
      fuzzyCompletion = true;
    };

    zsh = {
      enable = true;
    };
  };
}
