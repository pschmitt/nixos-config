final: prev:
let
  signalStack = final.stdenv.mkDerivation {
    pname = "full-nix-eza-signal-stack";
    version = "1";
    src = ./eza-stack.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall -Wextra -Werror "$src" -o stack.so
    '';
    installPhase = ''
      install -Dm755 stack.so $out/lib/stack.so
    '';
  };
in
{
  eza = final.symlinkJoin {
    name = "eza-full-nix";
    paths = [ prev.eza ];
    nativeBuildInputs = [ final.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/eza --prefix LD_PRELOAD : ${signalStack}/lib/stack.so
    '';
  };
  iputils = prev.iputils.overrideAttrs (old: {
    mesonFlags = old.mesonFlags ++ [ "-DUSE_CAP=false" ];
  });
}
