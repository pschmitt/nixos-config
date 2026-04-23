{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  bruvtabPkg = inputs.bruvtab.packages.${pkgs.stdenv.hostPlatform.system}.default;
  bruvtabChromeCrx = inputs.bruvtab.packages.${pkgs.stdenv.hostPlatform.system}.chromeCrx;
  bruvtabChromeExtensionId = lib.removeSuffix "\n" (
    builtins.readFile "${bruvtabChromeCrx}/extension-id"
  );
  bruvtabChromeExtensionJson = pkgs.writeText "${bruvtabChromeExtensionId}.json" (
    builtins.toJSON {
      external_crx = "${bruvtabChromeCrx}/bruvtab.crx";
      external_version = bruvtabPkg.version;
    }
  );
in
{

  # NOTE see also home-manager/gui/browser.nix
  programs.firefox = {
    enable = true;
    # nativeMessagingHosts.packages = with pkgs; [
    #   brotab
    #   tridactyl-native
    # ];
    #
    # preferences = {
    #   # Enable custom css (userChrome.css)
    #   "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    #   # Hide share indicator
    #   "privacy.webrtc.legacyGlobalIndicator" = false;
    #   "privacy.webrtc.hideGlobalIndicator" = true;
    #   # Prevent Firefox from Googling .lan addresses and opening them directly
    #   "browser.fixup.domainsuffixwhitelist.lan" = true;
    #   # Hide the "Summarize Page" button in the AI sidebar
    #   # https://www.reddit.com/r/firefox/comments/1o8zt65/how_do_i_remove_the_summarize_page_button_below/
    #   "browser.ml.chat.page" = false;
    # };
    #
    # preferencesStatus = "locked";
  };

  environment.systemPackages = with pkgs; [
    firefox
    google-chrome
  ];

  systemd.tmpfiles.rules = [
    "d /usr/share/google-chrome/extensions 0755 root root - -"
  ];

  system.activationScripts.bruvtabChromeExtension = {
    text = ''
      install -d -m0755 /usr/share/google-chrome/extensions
      for json in /usr/share/google-chrome/extensions/*.json
      do
        if [[ -f "$json" ]] && grep -Fq '/bruvtab.crx' "$json"
        then
          rm -f "$json"
        fi
      done
      install -m0444 ${bruvtabChromeExtensionJson} \
        /usr/share/google-chrome/extensions/${bruvtabChromeExtensionId}.json
      rm -f /usr/share/google-chrome/extensions/external_extensions.json
      rm -f /usr/share/google-chrome/extensions/${bruvtabChromeExtensionId}.crx
      rm -f /opt/google/chrome/extensions/*.json
    '';
  };
}

# vim: set ft=nix et ts=2 sw=2 :
