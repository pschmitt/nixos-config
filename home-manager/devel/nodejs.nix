{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    nodejs
  ];

  programs.npm = {
    package = pkgs.nodejs;
    settings = ''
      prefix=${config.xdg.dataHome}/npm
      cache=${config.xdg.cacheHome}/npm
      init-module=${config.xdg.configHome}/npm/config/npm-init.js
      logs-dir=${config.xdg.stateHome}/npm/logs
    '';
  };
}
