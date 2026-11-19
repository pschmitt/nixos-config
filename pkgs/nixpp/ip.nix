{
  callPackage,
  gnused,
  iproute2,
  lib,
  symlinkJoin,
  writeShellApplication,
}:
let
  rish = callPackage ./rish.nix { };
  wrapper = writeShellApplication {
    name = "ip";
    runtimeInputs = [ gnused ];
    text = ''
      nix_ip=${lib.escapeShellArg "${iproute2}/bin/ip"}
      shizuku_rish=${lib.escapeShellArg (lib.getExe rish)}
      ${builtins.readFile ./scripts/ip.sh}
    '';
  };
in
symlinkJoin {
  name = "termuxpp-iproute2";
  paths = [ iproute2 ];
  postBuild = ''
    ln -sfn ${lib.getExe wrapper} "$out/bin/ip"
  '';
  meta = {
    description = "iproute2 with a Shizuku fallback for Android network queries";
    mainProgram = "ip";
    platforms = [ "aarch64-linux" ];
  };
}
