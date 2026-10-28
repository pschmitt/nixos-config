# Keep the workstations' and lrz's current main systems in fnuc's store so they
# substitute them over the LAN from fnuc's Harmonia
# (profiles/features/network/fnuc-nix-cache.nix) instead of fetching from S3.
_: {
  imports = [ ../../services/harmonia-lan-mirror.nix ];

  # / and /nix share one filesystem with the Home Assistant VM. Let Nix
  # collect unrooted store paths itself when free space runs low, instead of
  # waiting for the weekly nix-gc (replaced mirror outputs become unrooted).
  nix.settings = {
    min-free = 75 * 1024 * 1024 * 1024;
    max-free = 150 * 1024 * 1024 * 1024;
  };

  services.harmonia.lanMirror = {
    enable = true;
    # Above min-free, so the mirror never relies on emergency GC.
    minFreeGiB = 100;
    # nixbot pins each default-branch attribute as nixbot-<repo>-<attr>
    # (nixos-config-private: services/scripts/nixbot-niks3-pin.sh).
    pins = {
      bucket = "nix-cache-brkn-lol";
      endpoint = "https://s3.openstack.de-west-01.wiit-cloud.io";
      profile = "niks3";
      prefix = "nixbot-pschmitt-nixos-config-";
    };
    targets = map (host: "hosts.${host}") [
      "ge2"
      "gk4"
      "lrz"
      "x13"
    ];
  };
}
