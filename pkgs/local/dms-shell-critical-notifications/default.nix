# Small set of visual patches on top of the upstream `dms-shell` package
# (dankMaterialShell.lib.mkDmsShell) that upstream has no settings for:
#
# 1. Critical-urgency notifications render with the same accent color as
#    every other notification (Theme.primary, the theme's general accent),
#    so on a dynamic/wallpaper-derived theme they look identical to normal
#    ones. Use the actual error/red color for the critical border + corner
#    ribbon instead, matching the color already used for the critical
#    popup's auto-dismiss timeout bar.
# 2. The Control Center's audio output/input rows fall back to the same
#    neutral Theme.surfaceText for "muted" as for "unmuted at 0%", so a
#    muted mic/speaker doesn't stand out in the widget itself (only the
#    transient OSD did). Use Theme.error for the muted case specifically.
# 3. DankSlider (the shared slider widget backing those same rows) has no
#    per-instance accent color either — its fill + thumb are hardcoded to
#    Style.primary. Add an optional activeColorOverride and wire the
#    output/input rows to redden the slider itself (not just the icon)
#    while muted.
# 4. The actual transient volume/mic OSD popups (VolumeOSD/MicVolumeOSD,
#    horizontal layout — what osdPosition: top-center actually shows) go
#    through OsdLevelRow, a third, separate slider wrapper untouched by
#    (2)/(3) above. Its fill/thumb stayed the stock blue on mute. Forward
#    activeColorOverride through OsdLevelRow to the same DankSlider patched
#    in (3), and wire both OSDs to redden on mute (VolumeOSD's icon didn't
#    even redden on mute upstream — MicVolumeOSD's already did).
# 5. ControlCenterButton (the persistent bar widget) embeds its own quick
#    audio/mic status icons with getMicIconColor()/getAudioIconColor()
#    helpers, yet another color path independent of (2)-(4) — muted never
#    returned Theme.error there either. Fix those two helpers.
#
# Each `--replace-fail` hard-fails the build if upstream's QML no longer
# matches, rather than silently patching the wrong thing — that's the
# signal to re-derive these snippets against the new source.
{
  inputs,
  pkgs,
}:
(inputs.dankMaterialShell.lib.mkDmsShell pkgs).overrideAttrs (old: {
  postInstall = old.postInstall + ''
    notif_dir="$out/share/quickshell/dms/Modules/Notifications"
    card="$notif_dir/Center/NotificationCard.qml"
    popup="$notif_dir/Popup/NotificationPopup.qml"

    substituteInPlace "$card" \
      --replace-fail 'return Theme.primarySelected;' 'return Theme.error;'
    substituteInPlace "$card" \
      --replace-fail $'                position: 0.0\n                color: Theme.primary' \
                      $'                position: 0.0\n                color: Theme.error'
    substituteInPlace "$card" \
      --replace-fail $'                position: 0.02\n                color: Theme.primary' \
                      $'                position: 0.02\n                color: Theme.error'

    substituteInPlace "$popup" \
      --replace-fail 'Theme.withAlpha(Theme.primary, 0.3)' 'Theme.withAlpha(Theme.error, 0.3)'
    substituteInPlace "$popup" \
      --replace-fail $'                    position: 0\n                    color: Theme.primary' \
                      $'                    position: 0\n                    color: Theme.error'
    substituteInPlace "$popup" \
      --replace-fail $'                    position: 0.02\n                    color: Theme.primary' \
                      $'                    position: 0.02\n                    color: Theme.error'

    cc_output="$out/share/quickshell/dms/Modules/ControlCenter/Widgets/AudioSliderRow.qml"
    cc_input="$out/share/quickshell/dms/Modules/ControlCenter/Widgets/InputAudioSliderRow.qml"

    substituteInPlace "$cc_output" \
      --replace-fail 'color: defaultSink?.audio && !defaultSink.audio.muted && defaultSink.audio.volume > 0 ? Theme.primary : Theme.surfaceText' \
                      'color: !defaultSink?.audio ? Theme.surfaceText : defaultSink.audio.muted ? Theme.error : defaultSink.audio.volume > 0 ? Theme.primary : Theme.surfaceText'

    substituteInPlace "$cc_input" \
      --replace-fail 'color: defaultSource?.audio && !defaultSource.audio.muted && defaultSource.audio.volume > 0 ? Theme.primary : Theme.surfaceText' \
                      'color: !defaultSource?.audio ? Theme.surfaceText : defaultSource.audio.muted ? Theme.error : defaultSource.audio.volume > 0 ? Theme.primary : Theme.surfaceText'

    slider="$out/share/quickshell/dms/DankCommon/Widgets/DankSlider.qml"

    substituteInPlace "$slider" \
      --replace-fail 'property real trackOpacity: usePopupTransparency ? Style.popupTransparency : 1.0' \
                      $'property real trackOpacity: usePopupTransparency ? Style.popupTransparency : 1.0\n    property var activeColorOverride: null'
    substituteInPlace "$slider" \
      --replace-fail 'color: slider.enabled ? Style.primary : Style.withAlpha(Style.onSurface, 0.12)' \
                      'color: slider.enabled ? (slider.activeColorOverride ? slider.activeColorOverride : Style.primary) : Style.withAlpha(Style.onSurface, 0.12)'

    substituteInPlace "$cc_output" \
      --replace-fail 'trackOpacity: root.sliderTrackOpacity' \
                      $'trackOpacity: root.sliderTrackOpacity\n        activeColorOverride: defaultSink?.audio?.muted ? Theme.error : null'
    substituteInPlace "$cc_input" \
      --replace-fail 'trackOpacity: root.sliderTrackOpacity' \
                      $'trackOpacity: root.sliderTrackOpacity\n        activeColorOverride: defaultSource?.audio?.muted ? Theme.error : null'

    osd_level_row="$out/share/quickshell/dms/Modules/OSD/OsdLevelRow.qml"
    volume_osd="$out/share/quickshell/dms/Modules/OSD/VolumeOSD.qml"
    mic_osd="$out/share/quickshell/dms/Modules/OSD/MicVolumeOSD.qml"

    substituteInPlace "$osd_level_row" \
      --replace-fail 'property real horizontalPadding: -1' \
                      $'property real horizontalPadding: -1\n    property var activeColorOverride: null'
    substituteInPlace "$osd_level_row" \
      --replace-fail 'thumbOutlineColor: root.thumbOutlineColor' \
                      $'thumbOutlineColor: root.thumbOutlineColor\n        activeColorOverride: root.activeColorOverride'

    substituteInPlace "$volume_osd" \
      --replace-fail 'iconName: AudioService.sinkVolumeIconName' \
                      $'iconName: AudioService.sinkVolumeIconName\n                iconColor: AudioService.sink?.audio?.muted ? Theme.error : Theme.surfaceText\n                activeColorOverride: AudioService.sink?.audio?.muted ? Theme.error : null'

    substituteInPlace "$mic_osd" \
      --replace-fail 'iconColor: AudioService.source?.audio?.muted ? Theme.error : Theme.surfaceText' \
                      $'iconColor: AudioService.source?.audio?.muted ? Theme.error : Theme.surfaceText\n                activeColorOverride: AudioService.source?.audio?.muted ? Theme.error : null'

    cc_button="$out/share/quickshell/dms/Modules/DankBar/Widgets/ControlCenterButton.qml"

    substituteInPlace "$cc_button" \
      --replace-fail $'        if (AudioService.source.audio.muted || AudioService.source.audio.volume === 0)\n            return Theme.surfaceText;\n        return Theme.widgetIconColor;' \
                      $'        if (AudioService.source.audio.muted)\n            return Theme.error;\n        if (AudioService.source.audio.volume === 0)\n            return Theme.surfaceText;\n        return Theme.widgetIconColor;'
    substituteInPlace "$cc_button" \
      --replace-fail $'    function getAudioIconColor() {\n        if (AudioService.sinkSilent)\n            return Theme.widgetInactiveIconColor;\n        return Theme.widgetIconColor;\n    }' \
                      $'    function getAudioIconColor() {\n        if (AudioService.sink?.audio?.muted)\n            return Theme.error;\n        if (AudioService.sinkSilent)\n            return Theme.widgetInactiveIconColor;\n        return Theme.widgetIconColor;\n    }'
  '';
})
