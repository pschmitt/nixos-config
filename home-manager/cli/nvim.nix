{
  inputs,
  pkgs,
  ...
}:
let
  # The unwrapped nightly binary from your flake input.
  nvimNightly = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.neovim;

  # DIRTYFIX load our regular init.lua (yadm-managed)
  sharedInitLua = ''
    dofile(vim.fn.stdpath("config") .. "/init.lua##class.notnixos")
  '';

  # Define common configuration to avoid duplication.
  commonConfig = {
    withRuby = false;
    withPython3 = false;

    extraPackages = with pkgs; [
      # vimPlugins.nvim-treesitter.withAllGrammars
      codespell
      tree-sitter

      # for random plugins that need to compile native extensions
      # eg: luasnip
      gcc

      # for copilot
      nodejs

      # for image.nvim, snacks.images etc.
      ghostscript
      imagemagick

      # ansible
      ansible-lint
      # ansible-language-server

      # docker
      docker-language-server
      dockerfile-language-server
      hadolint

      # golang
      go
      gopls

      # jsonnet
      jsonnet-language-server

      # lua
      luajit
      lua-language-server
      stylua

      # markdown
      marksman
      markdown-toc
      markdownlint-cli2

      # nix
      nil
      nixpkgs-fmt

      # python
      pyright
      ruff

      # shell
      bash-language-server
      shellcheck
      shfmt

      # tofu/terraform
      terraform-ls

      # toml
      taplo
    ];

    extraLuaPackages = ps: [ ps.magick ];
  };

  nvimNightlyLua = nvimNightly.lua.withPackages commonConfig.extraLuaPackages;

  nvimNightlyInitLua = pkgs.writeText "nvim-nightly-init.lua" sharedInitLua;

  nvimNightlyProviderLua = pkgs.neovimUtils.generateProviderRc {
    inherit (commonConfig) withPython3 withRuby;
    withNodeJs = false;
    withPerl = false;
  };

  nvimNightlyWrapped = pkgs.symlinkJoin {
    name = "nvim-nightly-wrapped";
    paths = [ nvimNightly ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f "$out/bin/nvim"
      makeWrapper ${nvimNightly}/bin/nvim "$out/bin/nvim" \
        --add-flags "--cmd" \
        --add-flags "lua ${nvimNightlyProviderLua}" \
        --set-default VIMINIT "lua dofile('${nvimNightlyInitLua}')" \
        --prefix PATH : ${
          pkgs.lib.makeBinPath (
            commonConfig.extraPackages
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.wl-clipboard ]
          )
        } \
        --prefix LUA_PATH ';' '${nvimNightly.lua.pkgs.luaLib.genLuaPathAbsStr nvimNightlyLua}' \
        --prefix LUA_CPATH ';' '${nvimNightly.lua.pkgs.luaLib.genLuaCPathAbsStr nvimNightlyLua}'
    '';
  };
in
{
  programs.neovim = commonConfig // {
    enable = true;
    viAlias = false;
    vimAlias = true;
    # DIRTYFIX load our regular init.lua (yadm-managed)
    initLua = sharedInitLua;
  };

  # Provide the nvim-nightly command.
  home.packages = [
    (pkgs.runCommand "nvim-nightly" { } ''
      mkdir -p $out/bin
      ln -s ${nvimNightlyWrapped}/bin/nvim $out/bin/nvim-nightly
    '')
  ];
}
