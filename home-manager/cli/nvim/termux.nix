{
  config,
  lib,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  config = lib.mkIf termuxMode {
    termux.packages = [ "neovim" ];

    xdg.configFile =
      import ./config-files.nix {
        appName = "nvim";
        inherit lib;
      }
      // {
        "nvim/init.lua".text = ''
          local config = vim.fn.stdpath("config") .. "/lua/config/"
          dofile(config .. "options.lua")
          dofile(config .. "autocmds.lua")
          dofile(config .. "keymaps.lua")
        '';
      };
  };
}
