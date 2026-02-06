{ pkgs, ... }:
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
}

# vim: set ft=nix et ts=2 sw=2 :
