{ lib, pkgs, ... }:
let
  inherit (lib.nixvim) mkRaw;

  gitsigns-yadm = pkgs.vimUtils.buildVimPlugin {
    pname = "gitsigns-yadm.nvim";
    version = "0-unstable-2026-07-12";
    src = pkgs.fetchFromGitHub {
      owner = "purarue";
      repo = "gitsigns-yadm.nvim";
      rev = "55575b2af68c0c6c73b1c1f8fe7c54e1e7fe8480";
      hash = "sha256-molMbuW1DD+9xCWLY9IQPxow6c8445tumsoUZYXuitw=";
    };
  };

  # Filetypes without whitespace highlighting/trimming
  whitespaceIgnoredFiletypes = [
    "diff"
    "git"
    "gitcommit"
    "qf"
    "help"
  ];
in
{
  # Plugins without any setup() to call (or set up from ../config/lua):
  extraPlugins = with pkgs.vimPlugins; [
    baleia-nvim # ANSI colors in the vimwiki sync log
    gitsigns-yadm
    obsidian-nvim # set up in config/notes.lua, only if the vault exists
    vim-suda # write as root (:SudaWrite, see write.lua)
    vim-abolish # :S/address{,es}/reference{,s}/g
    vimwiki
  ];

  plugins = {
    # The LazyVim look: icons, buffer tabs, noice messages/popups, which-key
    mini = {
      enable = true;
      mockDevIcons = true;
      modules = {
        ai = { };
        icons = { };
        pairs = {
          modes.command = true;
          skip_next = mkRaw ''[=[[%w%%%'%[%"%.%`%$]]=]'';
          skip_ts = [ "string" ];
          skip_unbalanced = true;
          markdown = true;
        };
      };
    };

    bufferline = {
      enable = true;
      settings.options = {
        always_show_bufferline = false;
        diagnostics = "nvim_lsp";
        close_command = mkRaw "function(n) Snacks.bufdelete(n) end";
        right_mouse_command = mkRaw "function(n) Snacks.bufdelete(n) end";
      };
    };

    noice = {
      enable = true;
      settings = {
        # Classic cmdline at the bottom, not the popup on top
        cmdline.view = "cmdline";
        lsp.override = {
          "vim.lsp.util.convert_input_to_markdown_lines" = true;
          "vim.lsp.util.stylize_markdown" = true;
          "cmp.entry.get_documentation" = true;
        };
        routes = [
          {
            filter = {
              event = "msg_show";
              any = [
                { find = "%d+L, %d+B"; }
                { find = "; after #%d+"; }
                { find = "; before #%d+"; }
              ];
            };
            view = "mini";
          }
        ];
        presets = {
          bottom_search = true;
          command_palette = true;
          long_message_to_split = true;
        };
      };
    };

    treesitter = {
      enable = true;
      highlight.enable = true;
      indent.enable = true;
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        bash
        c
        diff
        dockerfile
        fish
        git_config
        git_rebase
        gitcommit
        gitignore
        go
        gomod
        gosum
        hcl
        html
        hyprlang
        ini
        javascript
        jsdoc
        json
        jsonnet
        lua
        luadoc
        luap
        make
        markdown
        markdown_inline
        nix
        python
        query
        rasi
        regex
        terraform
        toml
        vim
        vimdoc
        xml
        yaml
        zsh
      ];
    };

    conform-nvim = {
      enable = true;
      # Format on save, as LazyVim did (toggle with <leader>uf for the
      # buffer, <leader>uF globally); <leader>F / :Format on demand.
      settings = {
        default_format_opts.lsp_format = "fallback";
        format_on_save = mkRaw ''
          function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
              return
            end
            return { timeout_ms = 1000, lsp_format = "fallback" }
          end
        '';
        formatters_by_ft = {
          lua = [ "stylua" ];
          python = [
            "isort"
            "black"
          ];
          nix = [ "nixfmt" ];
          sh = [ "shfmt" ];
          json = [ "prettier" ];
          markdown = [ "prettier" ];
          yaml = [ "prettier" ];
          toml = [ "taplo" ];
          go = [ "gofmt" ];
        };
      };
    };

    gitsigns = {
      enable = true;
      luaConfig.pre = ''
        require("gitsigns-yadm").setup({
          shell_timeout_ms = 2000,
          disable_inside_gitdir = false,
        })
      '';
      settings = {
        current_line_blame = true;
        signs = {
          add.text = "▎";
          change.text = "▎";
          delete.text = "";
          topdelete.text = "";
          changedelete.text = "▎";
          untracked.text = "▎";
        };
        # yadm support
        _on_attach_pre = mkRaw ''
          function(bufnr, callback)
            require("gitsigns-yadm").yadm_signs(callback, { bufnr = bufnr })
          end
        '';
      };
    };

    lualine = {
      enable = true;
      settings = {
        options = {
          component_separators = {
            left = "";
            right = "";
          };
          section_separators = {
            left = "";
            right = "";
          };
          globalstatus = true;
        };
        sections = {
          lualine_a = [ "mode" ];
          lualine_b = [
            "branch"
            "diff"
            "diagnostics"
          ];
          lualine_c = [ "filename" ];
          lualine_x = [ "filetype" ];
          lualine_y = [ ];
          lualine_z = [ "location" ];
        };
      };
    };

    nvim-surround.enable = true;

    snacks = {
      enable = true;
      settings = {
        bigfile.enabled = true;
        input.enabled = true;
        quickfile.enabled = true;
        scope.enabled = true;
        scroll.enabled = true;
        words.enabled = true;
        indent = {
          enabled = true;
          indent.char = "¦";
          animate.enabled = false;
        };
        notifier = {
          enabled = true;
          timeout = 3000;
          style = "compact";
        };
        picker = {
          enabled = true;
          matcher = {
            cwd_bonus = true;
            frecency = true;
            history_bonus = true;
          };
          # close the picker on ESC instead of going to normal mode
          win.input.keys."<Esc>" = {
            __unkeyed-1 = "close";
            mode = [
              "n"
              "i"
            ];
          };
        };
        styles.notification.wo.wrap = true;
      };
    };

    todo-comments = {
      enable = true;
      settings = {
        keywords = {
          FIXME = {
            icon = " ";
            color = "error";
          };
          TODO = {
            icon = " ";
            color = "info";
          };
          HACK = {
            icon = " ";
            color = "warning";
            alt = [ "DIRTYFIX" ];
          };
          WARN = {
            icon = " ";
            color = "warning";
            alt = [
              "WARNING"
              "XXX"
            ];
          };
          PERF = {
            icon = "󰾆 ";
            alt = [
              "OPTIM"
              "PERFORMANCE"
              "OPTIMIZE"
            ];
          };
          NOTE = {
            icon = " ";
            color = "hint";
            alt = [ "INFO" ];
          };
        };
        highlight.pattern = ''.*<(KEYWORDS):*\s+'';
      };
    };

    trim = {
      enable = true;
      settings = {
        ft_blocklist = whitespaceIgnoredFiletypes;
        trim_on_write = false;
        trim_trailing = true;
        trim_last_line = true;
        trim_first_line = true;
        highlight = true;
        highlight_bg = "#ff0000";
        highlight_ctermbg = "red";
        notifications = true;
      };
    };

    which-key = {
      enable = true;
      settings.preset = "helix";
    };
  };

  extraPackages = with pkgs; [
    # formatters (conform)
    black
    isort
    nixfmt
    prettier
    shfmt
    stylua
  ];
}
