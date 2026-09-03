# DankMaterialShell renders critical-urgency notifications with the same
# accent color as every other notification (Theme.primary, the theme's
# general accent), so on a dynamic/wallpaper-derived theme they look
# identical to normal ones. Patch the upstream `dms-shell` package
# (dankMaterialShell.lib.mkDmsShell) to use the actual error/red color
# for the critical border + corner ribbon instead, matching the color
# already used for the critical popup's auto-dismiss timeout bar.
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
  '';
})
