{ config, ... }:

{
  xdg.enable = true;

  home.sessionVariables = {
    GNUPGHOME = config.programs.gpg.homedir;
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    GOPATH = "${config.xdg.dataHome}/go";
    SQLITE_HISTORY = "${config.xdg.dataHome}/sqlite_history";
  };
}
