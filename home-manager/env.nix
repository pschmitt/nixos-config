{ config, ... }:

{
  xdg.enable = true;

  home.sessionVariables = {
    GNUPGHOME = "${config.xdg.configHome}/gnupg";
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    GOPATH = "${config.xdg.dataHome}/go";
    SQLITE_HISTORY = "${config.xdg.dataHome}/sqlite_history";
  };
}
