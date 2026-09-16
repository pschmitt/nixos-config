_: {
  users.users."monero-wallet-rpc-sync" = {
    isSystemUser = true;
    description = "Receives periodic monero-wallet-rpc snapshot pushes from rofl-12";
    group = "monero-wallet-rpc-sync";
    home = "/srv/monero-wallet-rpc";
    createHome = true;
    shell = "/run/current-system/sw/bin/bash";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAMYvXFI3Fxeaq4QTFhpHWOerN39NMKBkPeuucharvA2 monero-wallet-rpc-sync@rofl-12"
    ];
  };
  users.groups."monero-wallet-rpc-sync" = { };
}
