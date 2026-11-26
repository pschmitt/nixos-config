# How rworker shows workers booted from this image: the Glance image
# properties the publish effect (private services/nixbot-worker-image-effect.nix)
# sets at upload. rworker reads them per worker image for `ls`, the TUI and
# the web console. Each image variant sets its own values.
{ config, lib, ... }:
let
  cfg = config.rworker.image;
in
{
  options.rworker.image = {
    icon = lib.mkOption {
      type = lib.types.str;
      # nf-md-tools
      default = "U+F1064";
      example = "U+F0508";
      description = ''
        Nerd Font codepoint of the glyph shown for workers of this image
        (Glance property rworker_icon). A codepoint, not the glyph: Glance
        stores no 4-byte UTF-8, which the Material Design glyphs need.
      '';
    };
    label = lib.mkOption {
      type = lib.types.str;
      default = "build worker";
      description = "Display name of this image's workers (Glance property rworker_label).";
    };
    pool = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Autoscaler pool this image is built for, if any (Glance property rworker_pool).";
    };
    glanceProperties = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "The Glance properties the publish effect sets on this image.";
    };
  };

  config.rworker.image.glanceProperties = {
    rworker_icon = cfg.icon;
    rworker_label = cfg.label;
    # The account clients log into (rworker's worker module); the controller
    # records it for each worker booted from this image.
    rworker_login_user = config.rworker.worker.user;
  }
  // lib.optionalAttrs (cfg.pool != null) { rworker_pool = cfg.pool; };
}
