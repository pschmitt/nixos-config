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
  withSignalStack =
    package: programs:
    final.symlinkJoin {
      name = "${package.pname or package.name}-full-nix";
      paths = [ package ];
      passthru.fullNixSignalStackPrograms = programs;
      nativeBuildInputs = [ final.makeWrapper ];
      postBuild = final.lib.concatMapStringsSep "\n" (program: ''
        wrapProgram $out/bin/${program} --prefix LD_PRELOAD : ${signalStack}/lib/stack.so
      '') programs;
    };
in
{
  eza = withSignalStack prev.eza [ "eza" ];
  bat = withSignalStack prev.bat [ "bat" ];
  fd = withSignalStack prev.fd [ "fd" ];
  ripgrep = withSignalStack prev.ripgrep [ "rg" ];
  rbw = withSignalStack prev.rbw [
    "rbw"
    "rbw-agent"
  ];
  openstack-rs = withSignalStack prev.openstack-rs [ "osc" ];
  iputils = prev.iputils.overrideAttrs (old: {
    mesonFlags = old.mesonFlags ++ [ "-DUSE_CAP=false" ];
  });
}
