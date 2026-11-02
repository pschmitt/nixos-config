# WIIT CKS Nix cache (cks-nix-cache) as a substituter on work machines. The
# option and its per-host S3 credentials live in the private configuration.
_: {
  nix.wiitS3Cache.enable = true;
}
