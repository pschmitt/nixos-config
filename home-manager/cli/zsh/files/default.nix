let
  topics = [
    "awk"
    "calc"
    "cd"
    "countdown"
    "datetime"
    "debug"
    "diff"
    "echo"
    "emoji"
    "file"
    "find"
    "ntp"
    "osc8"
    "pulseaudio"
    "qrcode"
    "quote-cmd"
    "sed"
    "shebang"
    "shell"
    "sleep"
    "sqlite"
    "strings"
    "tsv"
    "versions"
    "watch"
    "whitespace"
  ];
in
{
  xdg.configFile = builtins.listToAttrs (
    builtins.concatMap (name: [
      {
        name = "zsh/functions/${name}";
        value = {
          source = ./functions + "/${name}";
          recursive = true;
        };
      }
      {
        name = "zsh/plugins/local/${name}.zsh";
        value.source = ./plugins/local + "/${name}.zsh";
      }
    ]) topics
  );
}
