{ config, ... }:

{
  xdg.enable = true;

  home.sessionVariables = {
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    GNUPGHOME = config.programs.gpg.homedir;
    GOPATH = "${config.xdg.dataHome}/go";
    SQLITE_HISTORY = "${config.xdg.dataHome}/sqlite_history";
  };
}
