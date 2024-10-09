{ inputs, pkgs, ... }:
{

  environment.systemPackages = with pkgs; [
    (vim_configurable.customize {
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

  programs.tmux = {
    enable = true;
    clock24 = true;
    newSession = true;
    terminal = "tmux-direct";
    aggressiveResize = true;
    # Set prefix to Ctrl-a
    shortcut = "a";
    keyMode = "vi";
    extraConfigBeforePlugins = ''
      set -g set-titles on
      set -g mouse on
    '';
    extraConfig = ''
      # binds
      # switch to main session
      unbind M
      bind M switch-client -t main

      # vertical split
      unbind S
      bind S split-window -v

      # disable confirmation when killing pane
      unbind x
      bind x kill-pane
    '';
    plugins = with pkgs.tmuxPlugins; [
      catppuccin
      fuzzback # prefix-?
      mode-indicator
      pain-control
      sensible
    ];
  };

  programs.npm = {
    enable = true;
    package = pkgs.nodePackages_latest.npm;
    # FIXME This does not seem to be enough to override the dirs npm uses
    # We might need to write this to /usr/etc/npmrc as the Arch Wiki suggests:
    # https://wiki.archlinux.org/title/XDG_Base_Directory
    npmrc = ''
      prefix=''${XDG_DATA_HOME}/npm
      cache=''${XDG_CACHE_HOME}/npm
      init-module=''${XDG_CONFIG_HOME}/npm/config/npm-init.js'
    '';
  };

  programs.neovim = {
    enable = true;
    package = inputs.neovim-nightly.packages.${pkgs.system}.default;

    defaultEditor = true;
    viAlias = false;
    vimAlias = true;

    configure = {
      packages.myVimPackage = with pkgs.vimPlugins; {
        start = [
          onedarkpro-nvim
          vim-oscyank
        ];
      };
      customRC = ''
        set nocompatible
        filetype plugin indent on
        syntax on
        scriptencoding utf-8
        set backspace=indent,eol,start
        set number
        set listchars=tab:→\ ,space:·,nbsp:␣,trail:•,eol:¶,precedes:«,extends:»

        " theme
        colorscheme onedark_vivid

        " enable modeline support
        set modeline

        " Mouse support
        set mouse=a

        " set space as leader
        nnoremap <SPACE> <Nop>
        let mapleader=" "

        " bindings
        nnoremap <leader>w :update<CR>
        nnoremap <leader>q :quitall!<CR>
        map Q :<C-u>quitall!<CR>
        " Toggle paste with F9
        " https://vim.fandom.com/wiki/Toggle_auto-indenting_for_code_paste
        nnoremap <F9> :set invpaste paste?<CR>
        set pastetoggle=<F9>

        " Spaces > Tabs
        set autoindent expandtab smarttab
        set tabstop=2
        set softtabstop=2
        set shiftwidth=2

        " 4 spaces for python files
        autocmd FileType python setlocal et ts=4 sts=4 sw=4

        " https://github.com/ojroques/vim-oscyank#advanced-usage
        let g:oscyank_silent = 1
        if (!has('nvim') && !has('clipboard_working'))
          " In the event that the clipboard isn't working, it's quite likely that
          " the + and * registers will not be distinct from the unnamed register. In
          " this case, a:event.regname will always be "" (empty string). However, it
          " can be the case that `has('clipboard_working')` is false, yet `+` is
          " still distinct, so we want to check them all.
          let s:VimOSCYankPostRegisters = ["", '+', '*']
          function! s:VimOSCYankPostCallback(event)
            if a:event.operator == 'y' && index(s:VimOSCYankPostRegisters, a:event.regname) != -1
              call OSCYankRegister(a:event.regname)
            endif
          endfunction
          augroup VimOSCYankPost
            autocmd!
            autocmd TextYankPost * call s:VimOSCYankPostCallback(v:event)
          augroup END
        endif
      '';
    };
  };

  programs.zsh = {
    enable = true;
    vteIntegration = true;
  };

  programs.fzf = {
    keybindings = true;
    fuzzyCompletion = true;
  };

  environment.variables = {
    FZF_DEFAULT_OPTS = "--ansi --history $HOME/.local/share/fzf_history --height 100% --info=inline";
  };

  environment.shells = with pkgs; [ zsh ];
  # Make ZSH respect XDG
  environment.etc = {
    "zshenv.local" = {
      text = ''
        export ZDOTDIR="$HOME/.config/zsh"
      '';
      mode = "0644";
    };
  };
}
