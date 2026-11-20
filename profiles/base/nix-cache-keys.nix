# Signing keys of our own binary caches: the build hosts, CI and the S3 cache.
# Trusted by every NixOS host (profiles/base/nix.nix) and by the TermuxPP
# guests for nixpp upgrades (modules/home-manager/termuxpp/cache.nix).
[
  "rofl-10:vYRBSypcO/0NnPsDxgSELIcJotU/LmZ1f6vZUKUmty0="
  "rofl-13:ESRCqy2jcftg690k98KSNqF6LgOqz1X7ZnXXE//WWD0="
  "rofl-14:XkEHSleW71wOnEnAcTZnYi/badnlAJAUxt6SIzbYsG8="
  "rofl-15:x68gyyrKadDfvJKdpPkRvmPckrYF6XqzlKaqs2xheVw="
  "rofl-16:DB8WQ415B8v3P9r1R8U4pO1iKrOAldbBHbSz+chryXI="
  # cache key we use in github actions for CI builds
  "gh-actions:x+pfxw4yRpZbonnjaCR0nIm5eN1wOGAki0soDQyFjJQ="
]
