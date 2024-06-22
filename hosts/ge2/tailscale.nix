{ ... }:

{
  services.tailscale.extraUpFlags = [
    "--accept-routes"
    "--advertise-exit-node"
  ];
}
