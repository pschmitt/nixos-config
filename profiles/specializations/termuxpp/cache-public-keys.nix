# Keys the TermuxPP guests trust for their signed systems: our caches' keys,
# shared with the NixOS hosts, plus the S3 cache's. Used by the guests' upgrade
# cache (modules/home-manager/termuxpp/cache.nix) and the bootstrap's
# `nixpp setup` config (setup-config.nix).
import ../../base/nix-cache-keys.nix
++ [
  "nix-cache.brkn.lol:k/zdgSv+6lcJ/9DRILjA7H18eIlFSA0OwzyqqXEwySM="
]
