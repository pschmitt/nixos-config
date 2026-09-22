{ config, inputs, ... }:
{
  imports = [ inputs.codex-ha-bridge.homeManagerModules.default ];

  services.codex-ha-bridge = {
    enable = true;
    environmentFile = config.sops.secrets."codex-ha-bridge/env".path;
  };

  sops.secrets."codex-ha-bridge/env".mode = "0600";
}
