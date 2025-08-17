{ pkgs, lib, ... }:

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

    patches = [ ./nrf-sniffer-filelock.patch ];

    nativeBuildInputs = [
      pkgs.makeWrapper
      python311Env
    ];

    installPhase = ''
      runHook preInstall

      libdir=$out/lib/nrf-sniffer
      bindir=$out/bin
      mkdir -p "$libdir" "$bindir"

      # Keep Python sources private
      cp -r extcap/SnifferAPI "$libdir/"
      install -m755 extcap/nrf_sniffer_ble.py "$libdir/nrf_sniffer_ble.py"

      # Pin the .py shebang to py311 inside libdir
      PATH=${lib.makeBinPath [ python311Env ]} patchShebangs "$libdir/nrf_sniffer_ble.py"

      # Single extcap launcher (no .py/.sh in extcap dir)
      makeWrapper "${python311Env}/bin/python3" "$bindir/nrf_sniffer_ble" \
        --set PYTHONPATH "$libdir" \
        --add-flags "$libdir/nrf_sniffer_ble.py" \
        --set PYTHONUNBUFFERED "1"

      runHook postInstall
    '';
  };
in
{
  # Install exactly one executable into Wireshark's extcap dir
  home.file.".local/lib/wireshark/extcap/nrf_sniffer_ble".source =
    "${nrfSnifferExtcap}/bin/nrf_sniffer_ble";

  home.packages = with pkgs; [ wireshark ];
}
