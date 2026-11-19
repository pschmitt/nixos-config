{
  callPackage,
  gnused,
  iproute2,
  lib,
  python3,
  rooted ? false,
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
      android_network_command=(${
        if rooted then "nixpp enter --outer -- su -c" else "${lib.escapeShellArg (lib.getExe rish)} -c"
      })
      json_ip=(${lib.getExe python3} ${./scripts/ip-json.py})
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
