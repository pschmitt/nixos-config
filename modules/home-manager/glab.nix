{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.glab;
  utils = import "${pkgs.path}/nixos/lib/utils.nix" {
    inherit lib config pkgs;
  };
  glabConfig = {
    git_protocol = cfg.gitProtocol;
    glamour_style = cfg.glamourStyle;
    check_update = cfg.checkUpdate;
    display_hyperlinks = cfg.displayHyperlinks;
    host = cfg.defaultHost;
    no_prompt = cfg.noPrompt;
    hosts = {
      "gitlab.com" = {
        api_protocol = "https";
        api_host = "gitlab.com";
        token._secret = config.sops.secrets."glab/gitlab.com/token".path;
      };
    }
    // lib.optionalAttrs cfg.work.enable {
      "${cfg.work.hostname}" = {
        token._secret = config.sops.secrets."glab/git.wiit.one/token".path;
        api_host = cfg.work.hostname;
        git_protocol = cfg.gitProtocol;
        api_protocol = "https";
        user = cfg.work.user;
        container_registry_domains = cfg.work.containerRegistryDomains;
      };
    };
  };
in
{
  options.custom.glab = {
    enable = lib.mkEnableOption "glab";

    defaultHost = lib.mkOption {
      type = lib.types.str;
      default = "gitlab.com";
      description = "Default GitLab host used by glab.";
    };

    gitProtocol = lib.mkOption {
      type = lib.types.enum [
        "ssh"
        "https"
      ];
      default = "ssh";
      description = "Git protocol used by glab.";
    };

    glamourStyle = lib.mkOption {
      type = lib.types.str;
      default = "dark";
      description = "glamour style for glab output.";
    };

    checkUpdate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether glab should check for updates.";
    };

    displayHyperlinks = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether glab should display hyperlinks.";
    };

    noPrompt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether glab should disable prompts.";
    };

    work = {
      enable = lib.mkEnableOption "work GitLab host in glab";

      hostname = lib.mkOption {
        type = lib.types.str;
        default = "git.wiit.one";
        description = "Work GitLab hostname.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "pschmitt";
        description = "Work GitLab username.";
      };

      containerRegistryDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "git.wiit.one"
          "git.wiit.one:443"
          "registry.git.wiit.one"
        ];
        description = "Container registry domains for the work GitLab instance.";
      };
    };
  };

  config = lib.mkMerge [
    {
      custom.glab.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = [ pkgs.glab ];

      sops.secrets."glab/gitlab.com/token" = {
        sopsFile = ../../secrets/shared.sops.yaml;
      };

      home.activation.glab-config = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        glab_config_dir="${config.xdg.configHome}/glab-cli"
        glab_config_file="$glab_config_dir/config.yml"

        $DRY_RUN_CMD mkdir -p "$glab_config_dir"
        $DRY_RUN_CMD rm -f "$glab_config_file"
        if [[ -z "''${DRY_RUN_CMD:-}" ]]
        then
          ${utils.genJqSecretsReplacementSnippet glabConfig "${config.xdg.configHome}/glab-cli/config.yml"}
          chmod 600 "$glab_config_file"
        fi
      '';
    })
  ];
}
