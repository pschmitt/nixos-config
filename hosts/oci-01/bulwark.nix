{
  config,
  lib,
  pkgs,
  ...
}:
let
  version = "1.21.3";
  release =
    {
      x86_64-linux = {
        arch = "amd64";
        hash = "sha256-mGaJdP7/ZKytFWzgOeubRRWUJcoyVSsGCx633FciI8s=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-jfGbDm3jBqALCcS86RxB9UOwWDlKsbo5E0h9r7DDQnk=";
      };
    }
    .${pkgs.stdenv.hostPlatform.system};
in
{
  services.bulwark = {
    enable = true;
    hostname = "127.0.0.1";
    port = 3037;
    # Keep the NixOS module while the nixpkgs package trails upstream security fixes.
    package = pkgs.stdenvNoCC.mkDerivation {
      pname = "bulwark";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/bulwarkmail/webmail/releases/download/${version}/bulwark-standalone-${version}-linux-${release.arch}.tar.gz";
        inherit (release) hash;
      };
      nativeBuildInputs = [
        pkgs.autoPatchelfHook
        pkgs.makeWrapper
      ];
      buildInputs = [ pkgs.stdenv.cc.cc.lib ];
      postPatch = ''
        # The release bundles both libc variants of sharp.
        rm -rf node_modules/@img/*-linuxmusl-*
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/share/bulwark" "$out/bin"
        cp -r . "$out/share/bulwark"
        makeWrapper ${lib.getExe pkgs.nodejs} "$out/bin/bulwark" \
          --add-flags "$out/share/bulwark/server.js" \
          --set NODE_ENV production
        runHook postInstall
      '';
      meta.mainProgram = "bulwark";
    };
    settings = {
      jmapServerUrl = "https://stalwart.${config.domains.main}";
      stalwartAdminAccess = "off";
      branding.appName = "Bulwark Mail";
    };
    updateCheck.enabled = false;
  };

}
