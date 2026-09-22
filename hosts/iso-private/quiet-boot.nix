{
  boot.kernelParams = [
    "quiet"
    "loglevel=0"
  ];

  boot.kernel.sysctl."kernel.printk" = "0 4 1 7";

  services.journald.extraConfig = ''
    ForwardToConsole=no
    # TTYPath=
    MaxLevelConsole=emerg
    MaxLevelKMsg=emerg
    Storage=volatile
  '';
}
