{ pkgs, lib, ... }:
let
  py = pkgs.python3.withPackages (ps: [
    ps.pyserial
    ps.psutil
  ]);

  nordicExtcap = pkgs.stdenv.mkDerivation {
    name = "nordic-ble-sniffer-extcap";
    src = pkgs.fetchzip {
      url = "https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/desktop-software/nrf-sniffer/sw/nrf_sniffer_for_bluetooth_le_4.1.1.zip";
      hash = "sha256-lmpTeGFCs/luNo9ygAt/uCfuoqoPBCPgsu44x4uL/zs=";
      stripRoot = false;
    };
    dontBuild = true;
    installPhase = ''
      set -e
      mkdir -p $out/lib/wireshark/extcap
      if [ -d extcap ]
      then
        cp -r extcap/* $out/lib/wireshark/extcap/
      elif [ -d nrf_sniffer_ble/extcap ]
      then
        cp -r nrf_sniffer_ble/extcap/* $out/lib/wireshark/extcap/
      else
        echo "Could not find extcap/ in Nordic ZIP layout" >&2
        exit 1
      fi
      chmod +x $out/lib/wireshark/extcap/*.py || true

      if [ -d profiles ]
      then
        mkdir -p $out/share/wireshark/profiles
        cp -r profiles/* $out/share/wireshark/profiles/
      fi
    '';
  };

  wiresharkWithSniffer = pkgs.symlinkJoin {
    name = "wireshark-with-nordic-sniffer";
    paths = [
      pkgs.wireshark
      nordicExtcap
    ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wireshark \
        --prefix PATH : ${py}/bin \
        --prefix PYTHONPATH : ${nordicExtcap}/lib/wireshark/extcap/SnifferAPI
      if [ -x $out/bin/tshark ]
      then
        wrapProgram $out/bin/tshark \
          --prefix PATH : ${py}/bin \
        --prefix PYTHONPATH : ${nordicExtcap}/lib/wireshark/extcap/SnifferAPI
      fi
    '';
  };
in
{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.segger-jlink.acceptLicense = true;

  nixpkgs.config.permittedInsecurePackages = [
    "segger-jlink-qt4-810"
  ];

  environment.systemPackages = with pkgs; [
    nrfutil
    nrf-udev
    nrfconnect
    nrfconnect-bluetooth-low-energy
  ];

  programs.wireshark = {
    enable = true;
    usbmon.enable = true;
    package = lib.mkForce wiresharkWithSniffer;
  };
}
