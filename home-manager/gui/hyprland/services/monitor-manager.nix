{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  luaBind = import ../lib/lua-bind.nix { inherit lib; };

  hostName = if osConfig != null then osConfig.networking.hostName or "" else "";
  isGk4 = hostName == "gk4";

  # Lua table fields for laptop monitor (host-specific, Nix-interpolated)
  luaLaptopFields = if isGk4 then "scale=1.666, transform=3" else "scale=1";

  # hyprctl keyword monitor suffix for laptop (host-specific)
  laptopScaleSuffix = if isGk4 then "1.666,transform,3" else "1";

  toggleScript = pkgs.writeShellScript "hypr-monitor-toggle" ''
    STATE_FILE="''${HOME}/.cache/hypr-monitor-state"
    JQ="${pkgs.jq}/bin/jq"

    get_monitor()
    {
      hyprctl monitors all -j | "$JQ" -r "$1"
    }

    LAPTOP=$(get_monitor '.[] | select(.name == "eDP-1") | .name // empty')
    LG=$(get_monitor '.[] | select(.description | test("LG Electronics.*WQHD")) | .name // empty')
    LENOVO=$(get_monitor '.[] | select(.description | test("Lenovo.*M14")) | .name // empty')

    if [[ -z "$LAPTOP" || -z "$LG" || -z "$LENOVO" ]]
    then
      exit 0
    fi

    mkdir -p "$(dirname "$STATE_FILE")"
    current=$(cat "$STATE_FILE" 2>/dev/null || true)

    if [[ "$current" == "triple-display-stacked" ]]
    then
      printf 'dual-display-no-internal' > "$STATE_FILE"
      hyprctl keyword monitor "$LG,3440x1440@60,0x0,1"
      hyprctl keyword monitor "$LENOVO,1920x1080@60,-1920x0,1"
      hyprctl keyword monitor "$LAPTOP,disable"
    else
      printf 'triple-display-stacked' > "$STATE_FILE"
      hyprctl keyword monitor "$LAPTOP,1920x1200@48,0x240,${laptopScaleSuffix}"
      hyprctl keyword monitor "$LG,3440x1440@59,1920x0,1"
      hyprctl keyword monitor "$LENOVO,1920x1080@60,986x1440,1"
    fi
  '';
in
{
  wayland.windowManager.hyprland = {
    extraConfig = ''
      do
        local STATE_FILE = (os.getenv("HOME") or "") .. "/.cache/hypr-monitor-state"

        local function read_state()
          local f = io.open(STATE_FILE, "r")
          if not f then return nil end
          local s = f:read("*l")
          f:close()
          return s
        end

        local function get_tags(monitors)
          local tags = {}
          for _, m in ipairs(monitors) do
            if m.name == "eDP-1" then
              tags.laptop = m
            elseif m.description and m.description:find("Lenovo.*M14") then
              tags.lenovo_m14 = m
            elseif m.description and m.description:find("LG Electronics.*WQHD") then
              tags.lg_wqhd = m
            elseif m.description and (m.description:find("PiKVM") or m.description:find("Synaptics Inc")) then
              tags.pikvm = m
            end
          end
          return tags
        end

        local function apply_laptop(output, position, mode)
          hl.monitor({output=output, mode=mode or "preferred", position=position, ${luaLaptopFields}})
        end

        local function apply_monitors()
          local monitors = hl.get_monitors()
          local tags = get_tags(monitors)
          local laptop = tags.laptop
          local lenovo = tags.lenovo_m14
          local lg     = tags.lg_wqhd
          local pikvm  = tags.pikvm
          local used   = {}

          if laptop and lenovo and lg and pikvm then
            -- dual-display-pikvm-with-internal: all four, laptop+pikvm disabled
            hl.monitor({output=lg.name,     mode="3440x1440@60", position="0x0",      scale=1})
            hl.monitor({output=lenovo.name,  mode="1920x1080@60", position="-1920x0",  scale=1})
            hl.monitor({output=pikvm.name,   disabled=true})
            hl.monitor({output=laptop.name,  disabled=true})
            used = {[lg.name]=true,[lenovo.name]=true,[pikvm.name]=true,[laptop.name]=true}
          elseif lenovo and lg and pikvm then
            -- dual-display-pikvm: lenovo + lg + pikvm, pikvm disabled
            hl.monitor({output=lg.name,     mode="3440x1440@60", position="0x0",      scale=1})
            hl.monitor({output=lenovo.name,  mode="1920x1080@60", position="-1920x0",  scale=1})
            hl.monitor({output=pikvm.name,   disabled=true})
            used = {[lg.name]=true,[lenovo.name]=true,[pikvm.name]=true}
          elseif laptop and lenovo and lg then
            -- three-monitor: dual-display-no-internal by default, triple-display-stacked via toggle
            if read_state() == "triple-display-stacked" then
              apply_laptop(laptop.name, "0x240", "1920x1200@48")
              hl.monitor({output=lg.name,    mode="3440x1440@59", position="1920x0",   scale=1})
              hl.monitor({output=lenovo.name, mode="1920x1080@60", position="986x1440", scale=1})
            else
              hl.monitor({output=lg.name,    mode="3440x1440@60", position="0x0",      scale=1})
              hl.monitor({output=lenovo.name, mode="1920x1080@60", position="-1920x0",  scale=1})
              hl.monitor({output=laptop.name, disabled=true})
            end
            used = {[lg.name]=true,[lenovo.name]=true,[laptop.name]=true}
          elseif lenovo and lg then
            -- dual-display: lenovo + lg, no laptop
            hl.monitor({output=lg.name,     mode="3440x1440@60", position="0x0",      scale=1})
            hl.monitor({output=lenovo.name,  mode="1920x1080@60", position="-1920x0",  scale=1})
            used = {[lg.name]=true,[lenovo.name]=true}
          elseif laptop and lg then
            -- laptop-lg-wqhd
            apply_laptop(laptop.name, "0x0")
            hl.monitor({output=lg.name, mode="3440x1440@60", position="auto-right", scale=1})
            used = {[laptop.name]=true,[lg.name]=true}
          elseif laptop and lenovo then
            -- laptop-edp-m14
            apply_laptop(laptop.name, "0x0")
            hl.monitor({output=lenovo.name, mode="preferred", position="auto-right", scale=1})
            used = {[laptop.name]=true,[lenovo.name]=true}
          elseif laptop then
            -- laptop only
            apply_laptop(laptop.name, "auto")
            used = {[laptop.name]=true}
          end

          for _, m in ipairs(monitors) do
            if not used[m.name] then
              hl.monitor({output=m.name, disabled=true})
            end
          end
        end

        hl.on("hyprland.start",  apply_monitors)
        hl.on("config.reloaded", apply_monitors)
        hl.on("monitor.added",   apply_monitors)
        hl.on("monitor.removed", apply_monitors)
      end
    '';

    settings.bind = [
      (luaBind.mkBind "SUPER SHIFT, M, exec, ${toggleScript}")
    ];
  };
}
