{ config, ... }:

{
  xdg.enable = true;

  home = {
    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.local/share/polaris/bin" # $ZPFX (zinit)
      "${config.home.homeDirectory}/bin"
    ];

    sessionVariables = {
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      GNUPGHOME = config.programs.gpg.homedir;
      GOPATH = "${config.xdg.dataHome}/go";
      SQLITE_HISTORY = "${config.xdg.dataHome}/sqlite_history";
    };
  };
}
