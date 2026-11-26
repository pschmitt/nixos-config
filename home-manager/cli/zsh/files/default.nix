{
  xdg.configFile = {
    "zsh/plugins/local/calc.zsh".source = ./plugins/local/calc.zsh;
    "zsh/plugins/local/datetime.zsh".source = ./plugins/local/datetime.zsh;
    "zsh/plugins/local/echo.zsh".source = ./plugins/local/echo.zsh;
    "zsh/functions/calc" = {
      source = ./functions/calc;
      recursive = true;
    };
    "zsh/functions/datetime" = {
      source = ./functions/datetime;
      recursive = true;
    };
    "zsh/functions/echo" = {
      source = ./functions/echo;
      recursive = true;
    };
  };
}
