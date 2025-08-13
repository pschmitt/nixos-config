{ ... }:
let
  networkId = "12ac4a1e716b9d7d";
in
{
  imports = [ ../monit/zerotier.nix ];

  # sops.secrets."zerotier/api-token" = {
  #   owner = "zeronsd";
  # };

  services.zerotierone = {
    enable = true;
    joinNetworks = [ networkId ];
    localConf = { };
  };

  # services.zeronsd = {
  #   servedNetworks."${networkId}" = {
  #     settings = {
  #       domain = "zerotier.internal";
  #       token = config.sops.secrets."zerotier/api-token".path;
  #     };
  #   };
  # };
}
