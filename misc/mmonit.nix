{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [ mmonit ];
  systemd.packages = [ pkgs.mmonit ];

  users.users.mmonit = {
    isSystemUser = true;
    home = "/var/lib/mmonit";
    createHome = true;
    group = "mmonit";
  };
  users.groups.mmonit = { };
}
