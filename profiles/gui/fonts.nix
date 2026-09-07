{ pkgs, ... }:

let
  # FIXME Is there any env var that GARNIX sets?
  isGarnix = builtins.getEnv "NOT_GARNIX" == "";
  # Only install proprietary fonts if not in CI
  conditionalPackages =
    pkgs:
    if isGarnix then
      [ ]
    else
      with pkgs;
      [
        ComicCode
        ComicCodeNF
        MonoLisa
        MonoLisa-Custom
        MonoLisa-CustomNF
      ];
in
{
  # NOTE You might need to run $ fc-cache -v --really-force as both your user and root
  # Also, removing ~/.config/fontconfig might help in case emojis are all fucked up and shit
  # The last time around the following command fixed emojis in pango apps:
  # rm -rf ~/.cache/fontconfig ~/.config/fontconfig; sudo fc-cache --really-force -v; fc-cache --really-force -v
  fonts = {
    packages =
      with pkgs;
      [
        # dejavu_fonts
        # noto-fonts-cjk
        fira-code
        fira-code-symbols
        liberation_ttf
        nerd-fonts.fira-code
        nerd-fonts.inconsolata
        nerd-fonts.terminess-ttf
        noto-fonts-color-emoji
        noto-fonts-color-emoji
        ubuntu-classic
        font-awesome
        font-awesome_5
      ]
      ++ (conditionalPackages pkgs);
    fontDir.enable = true;
    # enableDefaultFonts = true;  # deprecated in unstable
    enableDefaultPackages = true; # new option name (unstable)
    enableGhostscriptFonts = true;
    fontconfig = {
      enable = true;
      antialias = true;
      hinting.enable = true;
      # Family aliases that resolve to an italic face. Fontconfig picks the
      # Roman face for a bare family name (every Comic Code family ships both),
      # and a name like "ComicCode Nerd Font Italic" isn't a family at all — it
      # falls back to DejaVu. Toolkits normally ask for a slant alongside the
      # family, but some don't: Noctalia's text stack builds its Pango
      # descriptions with a family, a weight and a size only, so a plugin
      # label there can never request italics. These aliases are the way in —
      # ask for the alias family and fontconfig assigns the slant.
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <match target="pattern">
            <test name="family" compare="eq">
              <string>ComicCode Italic</string>
            </test>
            <edit name="family" mode="assign" binding="same">
              <string>ComicCode Nerd Font</string>
            </edit>
            <edit name="slant" mode="assign" binding="same">
              <const>italic</const>
            </edit>
          </match>
        </fontconfig>
      '';
      # defaultFonts = {
      #   serif = ["Noto Serif"];
      #   sansSerif = ["Noto Sans"];
      #   monospace = ["Comic Code Nerd Font"];
      #   emoji = ["Noto Color Emoji"];
      # };
    };
  };
}
