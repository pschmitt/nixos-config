{
  config,
  lib,
  ...
}:
{
  # Ensure timesyncd has primary servers so it does not remain in fallback-only idle state.
  services.timesyncd.servers = lib.mkDefault config.networking.timeServers;
}
