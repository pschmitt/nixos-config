{ config, ... }:
{
  sops.secrets = {
    "xmr/miners/cluster-01/context" = { };
    "xmr/miners/cluster-01/kubeconfig" = { };
    "xmr/miners/cluster-02/context" = { };
    "xmr/miners/cluster-02/kubeconfig" = { };
  };

  xmr.mining = {
    enable = true;
    clusters = {
      cluster-01 = {
        kubeContextFile = config.sops.secrets."xmr/miners/cluster-01/context".path;
        kubeconfigFile = config.sops.secrets."xmr/miners/cluster-01/kubeconfig".path;
        targetHost = "rofl-12";
        remoteKubeconfig = "/var/lib/ktunnel/kubeconfig-cluster-01";
        ktunnelService = "ktunnel-xmrig-proxy-cluster-01.service";
      };
      cluster-02 = {
        kubeContextFile = config.sops.secrets."xmr/miners/cluster-02/context".path;
        kubeconfigFile = config.sops.secrets."xmr/miners/cluster-02/kubeconfig".path;
        targetHost = "rofl-12";
        remoteKubeconfig = "/var/lib/ktunnel/kubeconfig-cluster-02";
        ktunnelService = "ktunnel-xmrig-proxy-cluster-02.service";
      };
    };
  };
}
