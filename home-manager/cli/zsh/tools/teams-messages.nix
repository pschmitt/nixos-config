{
  config,
  lib,
  pkgs,
  ...
}:
let
  completion = pkgs.linkFarm "zsh-completion-teams-messages" [
    {
      name = "_teams-messages";
      path = pkgs.writeText "zsh-completion-teams-messages" ''
        #compdef teams-messages

        _arguments \
          '(-h --help)'{-h,--help}'[Show help]' \
          '(-n --count)'{-n,--count}'[Maximum number of messages]:count:' \
          '(-u --unread)'{-u,--unread}'[Only the newest unread message of each chat]' \
          '(-c --channel)'{-c,--channel}'[Only channels/chats containing TEXT]:channel:' \
          '(-f --from)'{-f,--from}'[Only senders containing TEXT]:sender:' \
          '(-j --json)'{-j,--json}'[Raw JSON instead of a table]'
      '';
    }
  ];
in
{
  home.packages = [ pkgs.teams-messages ];

  xdg.configFile."zsh/completions/_teams-messages".source = "${completion}/_teams-messages";

  # The CLI reads HASS_SERVER/HASS_TOKEN; hass::secrets-setup provides them.
  programs.zsh.initContent = lib.mkIf (!(config.termux.enable or false)) (
    lib.mkOrder 620 ''
      teams-messages() {
        hass::secrets-setup || return 1
        command teams-messages "$@"
      }
    ''
  );
}
