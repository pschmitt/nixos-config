{
  lib,
  pkgs,
  stdenvNoCC,
  font-resizer,
  requireFile,
}:

stdenvNoCC.mkDerivation {
  pname = "ComicCodeNF";
  version = "478c9f6-lol";

  src = requireFile {
    name = "ILT-220422-478c9f6.zip";
    url = "https://blobs.brkn.lol/private/fonts/ILT-220422-478c9f6.zip";
    sha256 = "sha256-VS5kTzKd4Mi/kO68jEoLvvzv7AoFXs1eAN9XPJWAKSs=";
  };

  nativeBuildInputs = with pkgs; [
    nerd-font-patcher
    font-resizer
    unzip
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/opentype extracted
    unzip -j $src '*.otf' -d extracted

    for f in extracted/*
    do
      # only patch regular fonts
      case "$f" in
        *Demo*)
          continue
        ;;
      esac

      # patch font
      nerd-font-patcher \
        --complete \
        --no-progressbars \
        --outputdir "$out/share/fonts/opentype" \
        "$f" # || true  # /r/SomeOfYouMayDie
    done

    # Resize fonts (line height)
    for f in "$out/share/fonts/opentype"/*Nerd*.otf
    do
      font-resizer --scale 0.75 "$f"
    done

    # Remove original NerdFonts
    find "$out" -type f \( -name '*Nerd*' -and -not -name '*-resized*' \) -exec rm -f {} \;
  '';

  meta = with lib; {
    homepage = "https://tosche.net/fonts/comic-code";
    description = "Comic Code is a monospaced adaptation of the most infamous yet most popular casual font";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
