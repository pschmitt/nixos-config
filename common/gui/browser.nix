{ inputs, pkgs, ... }: {

  programs.firefox = {
    enable = true;
    # FIXME This does not seem to work.
    # See home-manager/home.nix for the dirty but working solution.
    nativeMessagingHosts.packages = with pkgs; [
      brotab
      # inputs.nix-agordoj.packages.${pkgs.system}.vdhcoapp
      tridactyl-native
    ];
    preferences = {
      # Enable custom css (userChrome.css)
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      # Hide share indicator
      "privacy.webrtc.legacyGlobalIndicator" = false;
      "privacy.webrtc.hideGlobalIndicator" = true;
      # Prevent Firefox from Googling .lan addresses and opening them directly
      "browser.fixup.domainsuffixwhitelist.lan" = true;
    };
    preferencesStatus = "user";
  };

  environment.systemPackages = with pkgs; [
    firefox
    google-chrome
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
