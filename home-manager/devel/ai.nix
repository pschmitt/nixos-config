{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  domainName =
    if osConfig != null && osConfig ? domains && osConfig.domains ? main then
      osConfig.domains.main
    else if config ? domains && config.domains ? main then
      config.domains.main
    else
      null;

  # External n8n skill set — https://github.com/czlonkowski/n8n-skills
  n8nSkillsSrc = pkgs.fetchFromGitHub {
    owner = "czlonkowski";
    repo = "n8n-skills";
    rev = "27e9d0ab92cccfc46db4f147497b173f214b69c5";
    hash = "sha256-D8wEZblUGWfXKIxw3TYXhZZ0P4C1lf71cSAVgjOpmes=";
  };

  skillSources = [
    ./skills
    "${n8nSkillsSrc}/skills"
    pkgs.todoist-cli.skill
  ];

  # Merge local skills with the upstream n8n skill set so all AI tools get both.
  # toString coerces the derivation to its store-path string, which the skills
  # option type accepts (it rejects raw derivations as it matches the attrsOf branch).
  allSkills = toString (
    pkgs.symlinkJoin {
      name = "ai-skills";
      paths = skillSources;
    }
  );

  # Codex does not appear to discover skills reliably when the top-level skill
  # directories are symlinks. Materialize a real directory tree for Codex while
  # keeping the shared symlinkJoin for the other AI clients.
  codexSkills = toString (
    pkgs.runCommand "codex-skills" { } ''
      mkdir -p "$out"
      ${lib.concatMapStringsSep "\n" (path: "cp -rL ${path}/. \"$out\"/") skillSources}
    ''
  );

  mcpHttpProxy =
    name:
    {
      url,
      tokenFile,
    }:
    pkgs.writeShellApplication {
      name = "${name}-mcp";
      runtimeInputs = [ pkgs.mcp-proxy ];
      text = ''
        token_file=${lib.escapeShellArg tokenFile}

        if [[ ! -r "$token_file" ]]; then
          printf 'MCP token file is not readable: %s\n' "$token_file" >&2
          exit 1
        fi

        API_ACCESS_TOKEN="$(<"$token_file")"
        export API_ACCESS_TOKEN

        exec mcp-proxy \
          "$@" \
          --transport streamablehttp \
          --verify-ssl ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          ${lib.escapeShellArg url}
      '';
    };

in
{
  assertions = [
    {
      assertion = domainName != null;
      message = ''
        Unable to determine the main domain for AI MCP configuration.
        Define `domains.main` in the standalone Home Manager host module or run this config under NixOS-backed Home Manager.
      '';
    }
  ];

  sops = {
    secrets = {
      "mistral-vibe/env" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "n8n/mcp/token" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "home-assistant/mcp/token" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
    };
  };

  programs.mcp = {
    enable = true;
    servers = {
      n8n-mcp = {
        command = "${
          mcpHttpProxy "n8n" {
            url = "https://n8n.${domainName}/mcp-server/http";
            tokenFile = config.sops.secrets."n8n/mcp/token".path;
          }
        }/bin/n8n-mcp";
      };
      home-assistant = {
        command = "${
          mcpHttpProxy "home-assistant" {
            url = "https://ha.${domainName}/api/mcp";
            tokenFile = config.sops.secrets."home-assistant/mcp/token".path;
          }
        }/bin/home-assistant-mcp";
      };
      obsidian = {
        command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
        args = [ "${config.xdg.userDirs.documents}/notes" ];
      };
      tmux = {
        command = "${pkgs.tmux-mcp}/bin/tmux-mcp-rs";
      };
    };
  };

  programs = {
    claude-code = {
      enable = true;
      package = pkgs.llm-agents.claude-code;
      skills = allSkills;
      enableMcpIntegration = true;
      settings = {
        skipDangerousModePermissionPrompt = true;
        theme = "dark";
      };
      rules = {
        context = ./CONTEXT.md;
      };
    };

    codex = {
      enable = true;
      package = pkgs.llm-agents.codex;
      context = ./CONTEXT.md;
      skills = codexSkills;
      enableMcpIntegration = true;
      settings = {
        projects = {
          "/etc/nixos".trust_level = "trusted";
          "/mnt/hass".trust_level = "trusted";
          "${config.home.homeDirectory}".trust_level = "trusted";
          "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git".trust_level = "trusted";
        };

        # model = "gpt-5.4";
        # model_reasoning_effort = "medium";
      };
    };

    antigravity-cli = {
      enable = true;
      package = pkgs.llm-agents.antigravity-cli;
      skills = allSkills;
      enableMcpIntegration = true;
      settings = {
        general = {
          preferredEditor = "nvim";
          previewFeatures = true;
          vimMode = false;

          sessionRetention = {
            enabled = true;
            maxAge = "30d";
            maxCount = 50;
          };
        };

        security = {
          auth = {
            selectedType = "oauth-personal";
          };
        };

        context = {
          loadMemoryFromIncludeDirectories = true;
          fileName = [
            "AGENTS.md"
            "CLAUDE.md"
            "CONTEXT.md"
            "GEMINI.md"
          ];
        };

        tools.shell.showColor = true;
      };
    };

    opencode = {
      enable = true;
      package = pkgs.llm-agents.opencode;
      skills = allSkills;
      context = builtins.readFile ./CONTEXT.md;
      web.enable = false;
      enableMcpIntegration = true;
    };

    github-copilot-cli = {
      enable = true;
      package = pkgs.llm-agents.copilot-cli;
      skills = allSkills;
      context = ./CONTEXT.md;
      enableMcpIntegration = true;
    };
  };

  # FIXME vibe-cli is broken as of 2026-02-25
  # Create ~/.config/vibe directory and .env file
  # xdg.configFile =
  #   let
  #     tomlFormat = pkgs.formats.toml { };
  #     vibeUpstreamCliPrompt = builtins.readFile "${pkgs.master.mistral-vibe.src}/vibe/core/prompts/cli.md";
  #     vibeCustomPromptId = "cli_context";
  #     vibeCustomPrompt = vibeUpstreamCliPrompt + "\n\n" + builtins.readFile ./CONTEXT.md;
  #   in
  #   {
  #     "vibe/.env".source =
  #       config.lib.file.mkOutOfStoreSymlink
  #         config.sops.secrets."mistral-vibe/env".path;
  #
  #     "vibe/config.toml".source = tomlFormat.generate "config.toml" {
  #       system_prompt_id = vibeCustomPromptId;
  #     };
  #
  #     "vibe/prompts/${vibeCustomPromptId}.md".text = vibeCustomPrompt;
  #   };

  home = {
    packages = with pkgs.llm-agents; [
      # vscode forks
      # antigravity
      # code-cursor

      # cli
      antigravity-cli
      # cursor-cli
      # kilocode-cli

      # FIXME vibe-cli is broken as of 2026-02-25
      # (pkgs.writeShellScriptBin "vibe" ''
      #   export VIBE_HOME="''${VIBE_HOME:-${config.xdg.configHome}/vibe}"
      #
      #   exec ${mistral-vibe}/bin/vibe "$@"
      # '')
    ];
  };
}
