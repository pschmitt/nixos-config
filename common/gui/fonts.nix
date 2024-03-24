{ pkgs, ... }: {
  # NOTE You might need to run $ fc-cache -v --really-force as both your user and root
  # Also, removing ~/.config/fontconfig might help in case emojis are all fucked up and shit
  # The last time around the following command fixed emojis in pango apps:
  # rm -rf ~/.cache/fontconfig ~/.config/fontconfig; sudo fc-cache --really-force -v; fc-cache --really-force -v
  fonts = {
    packages = with pkgs; [
      # dejavu_fonts
      # noto-fonts-cjk
      fira-code
      fira-code-symbols
      liberation_ttf
      nerdfonts
      noto-fonts
      noto-fonts-emoji
      ubuntu_font_family
      font-awesome
      font-awesome_5

      # proprietary fonts
      ComicCode
      ComicCodeNF
      MonoLisa
      MonoLisa-Custom
      MonoLisa-CustomNF
    ];
    fontDir.enable = true;
    # enableDefaultFonts = true;  # deprecated in unstable
    enableDefaultPackages = true; # new option name (unstable)
    enableGhostscriptFonts = true;
    fontconfig = {
      enable = true;
      antialias = true;
      hinting.enable = true;
      # defaultFonts = {
      #   serif = ["Noto Serif"];
      #   sansSerif = ["Noto Sans"];
      #   monospace = ["Comic Code Nerd Font"];
      #   emoji = ["Noto Color Emoji"];
      # };
    };
  };
}
