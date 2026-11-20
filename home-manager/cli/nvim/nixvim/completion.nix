{ lib, pkgs, ... }:
let
  inherit (lib.nixvim) mkRaw;

  plugin =
    {
      owner,
      repo,
      rev,
      hash,
      version,
    }:
    pkgs.vimUtils.buildVimPlugin {
      pname = repo;
      inherit version;
      src = pkgs.fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };
      # The cmp sources require("cmp"), which only blink.compat provides at runtime
      doCheck = false;
    };

  cmp-bruvtab = plugin {
    owner = "pschmitt";
    repo = "cmp-bruvtab";
    rev = "b6cb9f2eb6f80ca5c4631610e0aa5560525cca46";
    hash = "sha256-g8gcUn7G8acFMHN2EE2erKA0zKH2U86UuBE3YxYdxzk=";
    version = "0-unstable-2026-10-31";
  };

  cmp-nerdfont = plugin {
    owner = "chrisgrieser";
    repo = "cmp-nerdfont";
    rev = "e97482344ebed29093015a18c155057adf5c842b";
    hash = "sha256-alHMwjzYZO5rCgQUUUEcGNkW3PuYJFfGyo531wNw7p4=";
    version = "0-unstable-2024-11-27";
  };

  # nvim-cmp sources served through blink.compat
  compatSources = {
    bruvtab.enabled = mkRaw ''
      function()
        return not require("utils").is_termux() and vim.fn.executable("bruvtab") == 1
      end
    '';
    digraphs = { };
    nerdfont = { };
    tmux = { };
  };
in
{
  extraPlugins = [
    cmp-bruvtab
    cmp-nerdfont
    pkgs.vimPlugins.cmp-digraphs
    pkgs.vimPlugins.cmp-tmux
  ];

  plugins = {
    blink-compat.enable = true;
    blink-emoji.enable = true;
    friendly-snippets.enable = true;
    # friendly-snippets and ../config/snippets (package.json on the runtimepath)
    luasnip = {
      enable = true;
      fromVscode = [ { } ];
    };

    blink-cmp = {
      enable = true;
      settings = {
        keymap = {
          preset = "enter";
          # snippet jump, then Copilot ghost text, then a literal tab
          "<Tab>" = [
            "snippet_forward"
            (mkRaw "function() return vim.lsp.inline_completion.get() end")
            "fallback"
          ];
        };

        snippets.preset = "luasnip";
        signature.enabled = true;

        completion = {
          accept.auto_brackets.enabled = true;
          documentation = {
            auto_show = true;
            auto_show_delay_ms = 200;
          };
          menu.draw.treesitter = [ "lsp" ];
        };

        # Cmdline completions (:, /, ?, :!)
        cmdline = {
          enabled = true;
          keymap = {
            preset = "cmdline";
            "<Tab>" = [
              "show"
              "select_next"
            ];
            "<S-Tab>" = [ "select_prev" ];
          };
          # auto-show for ":" and ":!" (shell) prompts
          completion.menu.auto_show = mkRaw ''
            function()
              local t = vim.fn.getcmdtype()
              return t == ":" or t == "!"
            end
          '';
          # choose sources based on cmdline type
          sources = mkRaw ''
            function()
              local t = vim.fn.getcmdtype()
              if t == "/" or t == "?" then
                return { "buffer" }
              elseif t == ":" or t == "@" then
                return { "cmdline", "path", "buffer" }
              elseif t == "!" then
                return { "path", "buffer" }
              end
              return {}
            end
          '';
        };

        sources = {
          default = [
            "lsp"
            "path"
            "snippets"
            "buffer"
            "emoji"
            "omni"
          ]
          ++ lib.attrNames compatSources;

          providers = {
            emoji = {
              module = "blink-emoji";
              name = "Emoji";
              score_offset = 15;
              opts.insert = true;
            };
            # allow buffer words inside Ex commands like :%s, :g, etc.
            buffer.opts.enable_in_ex_commands = true;
          }
          // lib.mapAttrs (
            name: extra:
            {
              inherit name;
              module = "blink.compat.source";
              score_offset = -3;
            }
            // extra
          ) compatSources;
        };
      };
    };
  };
}
