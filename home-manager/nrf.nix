{
  pkgs,
  ...
}:

let
  python311Env = pkgs.python311.withPackages (ps: [
    ps.psutil
    ps.pyserial
  ]);

  snifferZip = pkgs.fetchzip {
    url = "https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/desktop-software/nrf-sniffer/sw/nrf_sniffer_for_bluetooth_le_4.1.1.zip";
    hash = "sha256-lmpTeGFCs/luNo9ygAt/uCfuoqoPBCPgsu44x4uL/zs=";
    stripRoot = false;
  };

  nrfSnifferExtcap = pkgs.stdenv.mkDerivation {
    pname = "nrf-sniffer-extcap";
    version = "4.1.1";
    src = snifferZip;

    # python311Env here so patchShebangs can resolve it
    nativeBuildInputs = [
      pkgs.makeWrapper
      python311Env
      pkgs.bash
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out

      cp -r "extcap/SnifferAPI" "$out/"
      install -m755 "extcap/nrf_sniffer_ble.py" "$out/nrf_sniffer_ble.py"

      patchShebangs "$out"

      runHook postInstall
    '';
  };

in
{
  # Install into Wireshark's user extcap path
  home.file.".local/lib/wireshark/extcap".source = nrfSnifferExtcap;

  # home.packages = with pkgs; [
  #   wireshark
  # ];
}
