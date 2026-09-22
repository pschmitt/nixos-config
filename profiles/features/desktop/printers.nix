{
  inputs,
  pkgs,
  ...
}:

{
  # Brother PT3000BT label printer
  environment.systemPackages = [
    inputs.printlabel.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  services.printing = {
    enable = true;
    drivers = with pkgs; [ cups-brother-hll2340dw ];
  };

  hardware.printers = {
    ensureDefaultPrinter = "bro";
    ensurePrinters = [
      {
        name = "bro";
        description = "Brother HL-L2340DW";
        deviceUri = "ipp://printer.lan:631";
        location = "home";
        model = "brother-HLL2340D-cups-en.ppd";
        ppdOptions = {
          PageSize = "A4";
          MediaType = "PLAIN";
          InputSlot = "TRAY1";
          Duplex = "None";
          Resolution = "600dpi";
          TonerSaveMode = "OFF";
        };
      }
    ];
  };
}
