{ lib, pkgs, pkgSource }:

pkgs.stdenv.mkDerivation rec {
  pname = "comic-code";
  version = "0.1.0";

  # src = ./ComicCode.tar.gz.age;
  # sshKey = builtins.readFile(decryptionKey);
  src = pkgSource;

  phases = [ "installPhase" ];
  # buildInputs = [ pkgs.age ];

  installPhase = ''
    mkdir -p $out/share/fonts
    ls -la ${src}
    tar -xzf $src -C $out/share/fonts/opentype/
    # cp -R $src $out/share/fonts/opentype/
  '';

  meta = with lib; {
    description = "Comic Code TTF Font (with NerdFont patches)";
    homepage = "https://tosche.net/fonts/comic-code";
    license = licenses.unfree;
    maintainers = with maintainers; [ pschmitt ];
  };
}
