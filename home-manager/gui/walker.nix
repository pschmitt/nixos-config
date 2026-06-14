{ pkgs, ... }:
let
  emojiList = pkgs.runCommand "emoji-fzf-list" { buildInputs = [ pkgs.emoji-fzf ]; } ''
    emoji-fzf preview --prepend > $out
  '';

  emojiCopyScript = pkgs.writeShellScript "elephant-emoji-copy" ''
    set -euo pipefail
    emoji="$1"
    printf '%s' "$emoji" | ${pkgs.wl-clipboard}/bin/wl-copy
    ${pkgs.libnotify}/bin/notify-send -a walker-menu "📋 Copied $emoji to clipboard"
    history_file="''${XDG_DATA_HOME:-$HOME/.local/share}/elephant/emoji-history"
    mkdir -p "$(dirname "$history_file")"
    tmpfile="$(mktemp)"
    {
      printf '%s\n' "$emoji"
      [[ -f "$history_file" ]] && ${pkgs.gnugrep}/bin/grep -vxF "$emoji" "$history_file" | head -49 || true
    } > "$tmpfile"
    mv "$tmpfile" "$history_file"
  '';

  emojiToggleFavScript = pkgs.writeShellScript "elephant-emoji-toggle-fav" ''
    set -euo pipefail
    emoji="$1"
    fav_file="''${XDG_DATA_HOME:-$HOME/.local/share}/elephant/emoji-favorites"
    mkdir -p "$(dirname "$fav_file")"
    tmpfile="$(mktemp)"
    if ${pkgs.gnugrep}/bin/grep -qxF "$emoji" "$fav_file" 2>/dev/null; then
      ${pkgs.gnugrep}/bin/grep -vxF "$emoji" "$fav_file" 2>/dev/null > "$tmpfile" || true
      mv "$tmpfile" "$fav_file"
      ${pkgs.libnotify}/bin/notify-send -a walker-menu "Removed $emoji from favorites" || true
    else
      { printf '%s\n' "$emoji"; cat "$fav_file" 2>/dev/null || true; } > "$tmpfile"
      mv "$tmpfile" "$fav_file"
      ${pkgs.libnotify}/bin/notify-send -a walker-menu "⭐ Added $emoji to favorites" || true
    fi
  '';
in
{
  services.elephant.enable = true;

  xdg.configFile."elephant/menus/emoji.lua".text = ''
    Name = "emoji"
    NamePretty = "Emoji"
    Icon = "face-smile"
    Terminal = false
    Cache = false
    FixedOrder = true
    Action = "${emojiCopyScript} %VALUE%"

    local DATA_DIR = (os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "") .. "/.local/share")) .. "/elephant"
    local EMOJI_LIST = "${emojiList}"
    local TOGGLE_FAV = "${emojiToggleFavScript}"

    local function read_list(path)
      local items, seen = {}, {}
      local f = io.open(path, "r")
      if f then
        for line in f:lines() do
          local e = line:match("^(.-)%s*$")
          if e and e ~= "" and not seen[e] then
            table.insert(items, e)
            seen[e] = true
          end
        end
        f:close()
      end
      return items, seen
    end

    local function parse_lines(fh)
      local emoji_map, ordered = {}, {}
      for line in fh:lines() do
        local emoji = line:match("^(%S+)")
        local name  = line:match("^%S+%s+(%S+)")
        local rest  = line:match("^%S+%s+%S+%s+(.+)$")
        if emoji then
          local entry = {
            Text    = name and name:gsub("_", " ") or emoji,
            Subtext = rest or "",
            Value   = emoji,
            Icon    = emoji,
          }
          if not emoji_map[emoji] then
            emoji_map[emoji] = entry
            table.insert(ordered, entry)
          end
        end
      end
      return emoji_map, ordered
    end

    local function make_entry(x, subtext)
      return {
        Text    = x.Text,
        Subtext = subtext,
        Value   = x.Value,
        Icon    = x.Icon,
        Actions = { ["toggle-favorite"] = TOGGLE_FAV .. " %VALUE%" },
      }
    end

    function GetEntries()
      local favorites, fav_set  = read_list(DATA_DIR .. "/emoji-favorites")
      local history,   hist_set = read_list(DATA_DIR .. "/emoji-history")

      local f = io.open(EMOJI_LIST, "r")
      local emoji_map, ordered = f and parse_lines(f) or {}, {}
      if f then f:close() end

      -- Merge custom aliases via jq (fast, avoids a Python spawn)
      local home = os.getenv("HOME") or ""
      local aliases_path = home .. "/.config/emoji-fzf/emojis.json"
      local af = io.open(aliases_path, "r")
      if af then
        af:close()
        local handle = io.popen(
          "jq -r '.[] | to_entries[] | .key + \" \" + (.value | join(\" \"))'"
          .. " " .. aliases_path .. " 2>/dev/null"
        )
        if handle then
          for line in handle:lines() do
            local emoji = line:match("^(%S+)")
            local extra = line:match("^%S+%s+(.+)$")
            if emoji and extra then
              if emoji_map[emoji] then
                emoji_map[emoji].Subtext = emoji_map[emoji].Subtext .. " " .. extra
              else
                local e = { Text = emoji, Subtext = extra, Value = emoji, Icon = emoji }
                emoji_map[emoji] = e
                table.insert(ordered, e)
              end
            end
          end
          handle:close()
        end
      end

      local result = {}

      for _, e in ipairs(favorites) do
        local x = emoji_map[e]
        if x then table.insert(result, make_entry(x, "⭐ favorite")) end
      end

      for _, e in ipairs(history) do
        if not fav_set[e] then
          local x = emoji_map[e]
          if x then table.insert(result, make_entry(x, "recently used")) end
        end
      end

      for _, e in ipairs(ordered) do
        if not fav_set[e.Value] and not hist_set[e.Value] then
          table.insert(result, make_entry(e, e.Subtext))
        end
      end

      return result
    end
  '';

  services.walker = {
    enable = true;
    systemd.enable = true;
    settings = {
      app_launch_prefix = "uwsm app -- ";
      keybinds.quick_activate = [
        "alt 1"
        "alt 2"
        "alt 3"
        "alt 4"
      ];
      theme = "justgray";
      modules = [ { name = "menus"; } ];
      providers.actions = {
        "menus:emoji" = [
          {
            action = "default";
            bind = "Return";
            default = true;
            after = "Close";
          }
          {
            action = "toggle-favorite";
            bind = "ctrl f";
            label = "⭐ Favorite";
            after = "AsyncReload";
          }
        ];
      };
    };
    theme = {
      name = "justgray";
      style = ''
        @define-color foreground #C7CCD1;
        @define-color background #24282F;
        @define-color surface #2E2E2E;
        @define-color overlay #383838;
        @define-color muted #717171;
        @define-color accent #A6A6A6;

        * {
          all: unset;
        }

        window {
          background: transparent;
        }

        .box-wrapper {
          background: @background;
          border-radius: 12px;
          min-width: 800px;
          padding: 20px;
          border: 1px solid @overlay;
          box-shadow:
            0 19px 38px rgba(0, 0, 0, 0.5),
            0 15px 12px rgba(0, 0, 0, 0.3);
          color: @foreground;
          font-family: "ComicCode Nerd Font", monospace;
          font-size: 17px;
        }

        .search-container {
          background: @surface;
          border-radius: 6px;
          padding: 10px 14px;
          margin-bottom: 8px;
        }

        .input {
          color: @foreground;
          font-size: 18px;
        }

        .input placeholder {
          color: @muted;
          opacity: 0.8;
        }

        scrollbar {
          opacity: 0;
        }

        child {
          border-radius: 6px;
          margin: 2px 0;
        }

        .item-box {
          padding: 8px 10px;
          border-radius: 6px;
        }

        .normal-icons {
          -gtk-icon-size: 24px;
        }

        .large-icons {
          -gtk-icon-size: 42px;
        }

        .item-image {
          margin-right: 10px;
        }

        .item-image-text {
          font-size: 34px;
        }

        child:selected .item-box,
        row:selected .item-box {
          background: @overlay;
        }

        .item-text {
          color: @foreground;
          font-weight: 500;
          font-size: 20px;
        }

        child:selected .item-text,
        row:selected .item-text {
          color: @accent;
        }

        .item-subtext {
          color: @muted;
          font-size: 0.95em;
        }

        .item-quick-activation {
          color: @muted;
        }

        child:selected .item-quick-activation,
        row:selected .item-quick-activation {
          color: @accent;
        }

        .keybinds {
          color: @muted;
          font-size: 14px;
          padding-top: 10px;
          border-top: 1px solid @overlay;
          margin-top: 6px;
        }

        .error {
          background: rgba(191, 97, 106, 0.4);
          border-radius: 4px;
          padding: 8px;
          color: @foreground;
        }

        .placeholder,
        .elephant-hint {
          color: @muted;
        }
      '';
    };
  };
}
