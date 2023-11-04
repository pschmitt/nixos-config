{ inputs, lib, config, pkgs, ... }: {
  programs.firefox = {
    nativeMessagingHosts.packages = with pkgs; [
      fx-cast-bridge
    ];
  };

  environment.systemPackages = with pkgs; [
    fx-cast-bridge
  ];

  systemd.user.services.fx-cast = {
    description = "fx-cast-bridge";
    documentation = [ "https://hensm.github.io/fx_cast/" ];

    serviceConfig = {
      ExecStart = "${pkgs.fx-cast-bridge}/bin/fx_cast_bridge -d";
    };

    wantedBy = [ "default.target" ];
  };
}
