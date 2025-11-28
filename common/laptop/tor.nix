{ lib, ... }:
{
  imports = [ ../../services/tor.nix ];

  # Disable the tor service by default
  systemd.services.tor.wantedBy = lib.mkForce [ ];
}
