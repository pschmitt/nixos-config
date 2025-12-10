{ config, pkgs, ... }:
{
  # Define the systemd service
  systemd.services."git-clone-nixos-config" = {
    # Make sure the service waits for networking to be up
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScriptBin "git-clone-nixos-config" ''
        # Check if /etc/nixos is empty
        if [[ -z "$(ls -A /etc/nixos)" ]]
        then
          ${pkgs.git}/bin/git clone https://github.com/pschmitt/nixos-config /etc/nixos
          ${pkgs.coreutils}/bin/chown -R ${config.mainUser.username} /etc/nixos
        fi
      ''}/bin/git-clone-nixos-config";
    };
  };
}
