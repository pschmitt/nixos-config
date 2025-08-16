{ pkgs, lib, ... }:
let
  py = pkgs.python3.withPackages (ps: [
    ps.pyserial
    ps.psutil
  ]);

  wiresharkWithPy = pkgs.symlinkJoin {
    name = "wireshark-with-python-deps";
    paths = [ pkgs.wireshark ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wireshark \
        --prefix PATH : ${py}/bin \
        --set PYTHONNOUSERSITE 1
      if [ -x $out/bin/tshark ]
      then
        wrapProgram $out/bin/tshark \
          --prefix PATH : ${py}/bin \
          --set PYTHONNOUSERSITE 1
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
    # nrf-command-line-tools
    nrfutil
    nrf-udev
    nrfconnect
    nrfconnect-bluetooth-low-energy
  ];

  programs.wireshark = {
    enable = true;
    package = lib.mkForce wiresharkWithPy;
  };
}
