{ lib }:
let
  inherit (lib) generators;

  toLua = generators.toLua { };
  mkInline = generators.mkLuaInline;

  trim = lib.strings.trim;
  nonEmpty = value: value != "";
  joinComma = lib.concatStringsSep ", ";
  joinSpace = lib.concatStringsSep " ";

  direction =
    value:
    {
      l = "left";
      r = "right";
      u = "up";
      d = "down";
      left = "left";
      right = "right";
      up = "up";
      down = "down";
    }
    .${value} or value;

  workspaceValue =
    value:
    if builtins.match "-?[0-9]+" value != null then toString (builtins.fromJSON value) else toLua value;

  keyString =
    mods: key: lib.concatStringsSep " + " ((lib.filter nonEmpty (lib.splitString " " mods)) ++ [ key ]);

  hyprctlDispatch =
    dispatcher: args:
    let
      dispatchArgs = joinSpace args;
      command =
        "hyprctl dispatch ${dispatcher}" + lib.optionalString (dispatchArgs != "") " ${dispatchArgs}";
    in
    "hl.dsp.exec_cmd(${toLua command})";

  dispatcherExpr =
    dispatcher: args:
    if dispatcher == "exec" then
      "hl.dsp.exec_cmd(${toLua (joinComma args)})"
    else if dispatcher == "submap" then
      "hl.dsp.submap(${toLua (lib.elemAt args 0)})"
    else if dispatcher == "resizeactive" then
      let
        xy = lib.splitString " " (lib.elemAt args 0);
      in
      "hl.dsp.window.resize({x=${lib.elemAt xy 0}, y=${lib.elemAt xy 1}, relative=true})"
    else if dispatcher == "movewindow" && args == [ ] then
      "hl.dsp.window.drag()"
    else if dispatcher == "resizewindow" && args == [ ] then
      "hl.dsp.window.resize()"
    else if dispatcher == "movefocus" then
      "hl.dsp.focus({direction=${toLua (direction (lib.elemAt args 0))}})"
    else if dispatcher == "workspace" then
      "hl.dsp.focus({workspace=${workspaceValue (lib.elemAt args 0)}})"
    else if dispatcher == "focusmonitor" then
      "hl.dsp.focus({monitor=${toLua (lib.elemAt args 0)}})"
    else if dispatcher == "movecursortocorner" then
      "hl.dsp.cursor.move_to_corner({corner=${lib.elemAt args 0}})"
    else if dispatcher == "togglefloating" then
      "hl.dsp.window.float()"
    else if dispatcher == "layoutmsg" then
      "hl.dsp.layout(${toLua (joinSpace args)})"
    else if dispatcher == "pseudo" then
      "hl.dsp.window.pseudo()"
    else if dispatcher == "killactive" then
      "hl.dsp.window.close()"
    else if dispatcher == "togglegroup" then
      "hl.dsp.group.toggle()"
    else if dispatcher == "moveoutofgroup" then
      "hl.dsp.window.move({out_of_group=true})"
    else if dispatcher == "movetoworkspace" then
      "hl.dsp.window.move({workspace=${workspaceValue (lib.elemAt args 0)}})"
    else if dispatcher == "changegroupactive" then
      "hl.dsp.group.next()"
    else if dispatcher == "fullscreen" then
      if args == [ "1" ] then
        ''hl.dsp.window.fullscreen({mode="maximized"})''
      else
        "hl.dsp.window.fullscreen()"
    else if dispatcher == "fullscreenstate" then
      ''hl.dsp.window.fullscreen_state({internal=${lib.elemAt args 0}, client=${lib.elemAt args 1}, action="set"})''
    else if dispatcher == "swapnext" then
      "hl.dsp.window.swap({next=true})"
    else
      hyprctlDispatch dispatcher args;

  parseLegacy =
    row:
    let
      parts = map trim (lib.splitString "," row);
      mods = lib.elemAt parts 0;
      key = lib.elemAt parts 1;
      dispatcher = lib.elemAt parts 2;
      args = lib.filter nonEmpty (lib.drop 3 parts);
    in
    {
      key = keyString mods key;
      dispatcher = mkInline (dispatcherExpr dispatcher args);
    };

  splitFirstWord =
    value:
    let
      words = lib.splitString " " value;
    in
    {
      first = lib.elemAt words 0;
      rest = joinSpace (lib.drop 1 words);
    };

  parseRuleValue =
    key: value:
    if
      builtins.elem key [
        "workspace"
        "suppress_event"
        "idle_inhibit"
        "fullscreen_state"
        "monitor"
        "group"
        "animation"
        "tag"
        "content"
        "opacity"
      ]
    then
      value
    else if value == "on" then
      true
    else if value == "off" then
      false
    else if builtins.match "-?[0-9]+" value != null then
      builtins.fromJSON value
    else
      value;

  mergeRulePart =
    acc: part:
    if lib.hasPrefix "match:" part then
      let
        parsed = splitFirstWord (lib.removePrefix "match:" part);
      in
      acc
      // {
        match = (acc.match or { }) // {
          ${parsed.first} = parsed.rest;
        };
      }
    else
      let
        parsed = splitFirstWord part;
      in
      acc
      // {
        ${parsed.first} = parseRuleValue parsed.first parsed.rest;
      };
in
rec {
  mkLuaBind = key: dispatcher: opts: {
    _args = [
      key
      dispatcher
    ]
    ++ lib.optional (opts != { }) opts;
  };

  mkBindWith =
    opts: row:
    let
      parsed = parseLegacy row;
    in
    mkLuaBind parsed.key parsed.dispatcher opts;

  mkBind = mkBindWith { };
  mkRepeatingBind = mkBindWith { repeating = true; };
  mkLockedBind = mkBindWith { locked = true; };
  mkReleaseTransparentBind = mkBindWith {
    release = true;
    transparent = true;
  };

  execCmd = cmd: mkInline "hl.dsp.exec_cmd(${toLua cmd})";
  submapTo = name: mkInline "hl.dsp.submap(${toLua name})";
  resizeActive =
    x: y: mkInline "hl.dsp.window.resize({x=${toString x}, y=${toString y}, relative=true})";
  sendShortcut =
    mods: key: target:
    mkInline "hl.dsp.send_shortcut({mods=${toLua mods}, key=${toLua key}, window=${toLua target}})";

  mkWindowRule = row: lib.foldl' mergeRulePart { } (map trim (lib.splitString "," row));
}
