{
  config,
  lib,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxYqo = import ./config/termux-yqo.nix;
  termuxFunctions = ''
    ping() {
      local -a ipv4 ipv6
      zparseopts -E -D 4=ipv4 6=ipv6

      if (( ''${#ipv6} ))
      then
        command ping6 "$@"
      else
        command ping "$@"
      fi
    }
  '';
  termuxFunctionInit =
    if termuxMode then
      termuxFunctions
    else
      ''
        if is_termux
        then
          ${termuxYqo}
          ${termuxFunctions}
        fi
      '';
  hashdirBody = ''
    if (( $+functions[hashdir] ))
    then
      [[ -d "$XDG_DOCUMENTS_DIR" ]] && hashdir "$XDG_DOCUMENTS_DIR" docs
      [[ -d "$XDG_DOCUMENTS_DIR/notes" ]] && hashdir "$XDG_DOCUMENTS_DIR/notes" notes
      [[ -d "$XDG_PICTURES_DIR" ]] && hashdir "$XDG_PICTURES_DIR" pics
    fi
  '';
  hashdirInit =
    if termuxMode then
      hashdirBody
    else
      ''
        if is_termux
        then
          ${hashdirBody}
        fi
      '';
  yadmClassBody = ''
    if (( $+commands[yadm] ))
    then
      () {
        local class classes changed
        classes="$(yadm config --get-all local.class)"

        for class in termux impure
        do
          if ! grep -qx "$class" <<< "$classes"
          then
            yadm config --add local.class "$class"
            changed=1
          fi
        done

        if [[ -n "$changed" ]]
        then
          yadm alt
        fi
      }
    fi
  '';
  yadmClassInit =
    if termuxMode then
      yadmClassBody
    else
      ''
        if is_termux
        then
          ${yadmClassBody}
        fi
      '';
in
{
  programs.vivid.activeTheme = lib.mkForce "catppuccin-mocha";

  programs.zsh = {
    shellAliases = {
      y = lib.mkForce "apt search";
      ync = lib.mkForce "pkg install -y";
      yqq = lib.mkForce "apt-cache policy";
      yrm = lib.mkForce "pkg remove -y";
    };

    envExtra = ''
      typeset -U path
      path=(
        "$HOME/bin"
        "$CARGO_HOME/bin"
        "$GOPATH/bin"
        "$XDG_DATA_HOME/luarocks/bin"
        "$HOME/.local/bin"
        "$XDG_DATA_HOME/krew/bin"
        "$XDG_DATA_HOME/asdf/shims"
        "$XDG_DATA_HOME/npm/bin"
        $path
      )

      ${
        if termuxMode then
          ''
            path+=(/system/bin)
            path=("''${(@)path:#/bin}")
          ''
        else
          ''
            if (( $+commands[termux-info] ))
            then
              path+=(/system/bin)
              path=("''${(@)path:#/bin}")
          ''
      }

      export XDG_DOCUMENTS_DIR="$HOME/storage/shared/Documents"
      export XDG_DOWNLOAD_DIR="$HOME/storage/shared/Download"
      export XDG_MUSIC_DIR="$HOME/storage/shared/Music"
      export XDG_PICTURES_DIR="$HOME/storage/shared/Pictures"
      export XDG_VIDEOS_DIR="$HOME/storage/shared/Videos"
      if [[ -d "$HOME/storage" ]]
      then
        export XDG_DOWNLOAD_DIR="$HOME/storage/downloads"
        export XDG_PICTURES_DIR="$HOME/storage/pictures"
      fi
      ${lib.optionalString (!termuxMode) "fi"}
    '';

    initContent = lib.mkMerge [
      (lib.mkOrder 600 termuxFunctionInit)
      (lib.mkOrder 615 hashdirInit)
      (lib.mkOrder 620 yadmClassInit)
    ];
  };
}
