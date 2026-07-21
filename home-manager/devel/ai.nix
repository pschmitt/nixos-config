{
  config,
  lib,
  pkgs,
  ...
}:
let
  domainName = config.domains.main;

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
  ]
  ++ config.custom.aiSkills.extraSources;

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

  # Remote (streamable-HTTP) MCP server reached through mcp-proxy. The bearer
  # token is injected via `env.API_ACCESS_TOKEN.file`: home-manager's MCP module
  # generates a wrapper that reads the sops secret at startup (see
  # lib.hm.mcp.wrapEnvFilesCommand), so no hand-rolled token-reading script is
  # needed.
  mcpHttpProxy =
    {
      url,
      tokenFile,
    }:
    {
      command = "${pkgs.mcp-proxy}/bin/mcp-proxy";
      args = [
        "--transport"
        "streamablehttp"
        "--verify-ssl"
        "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        url
      ];
      env.API_ACCESS_TOKEN.file = tokenFile;
    };

in
{
  options.custom.aiSkills.extraSources = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = ''
      Extra skill-set directories merged in alongside ./skills (each is a
      container of named skill subdirectories, same shape as ./skills
      itself), for skills contributed by other modules on this same host
      (e.g. a private flake input's own skills, not fit for the public
      repo).
    '';
  };

  config = {
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
        n8n-mcp = mcpHttpProxy {
          url = "https://n8n.${domainName}/mcp-server/http";
          tokenFile = config.sops.secrets."n8n/mcp/token".path;
        };
        home-assistant = mcpHttpProxy {
          url = "https://ha.${domainName}/api/mcp";
          tokenFile = config.sops.secrets."home-assistant/mcp/token".path;
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
          approval_policy = "never";
          approvals_reviewer = "user";
          check_for_update_on_startup = false;
          model = "gpt-5.4";
          model_reasoning_effort = "medium";
          notice.model_migrations = {
            "gpt-5.4" = "gpt-5.5";
          };

          tui.model_availability_nux = {
            "gpt-5.5" = 4;
          };

          projects = {
            "/etc/nixos".trust_level = "trusted";
            "/mnt/ha".trust_level = "trusted";
            "/mnt/turris".trust_level = "trusted";
            "${config.home.homeDirectory}".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git".trust_level = "trusted";
          };

          sandbox_mode = "danger-full-access";
          features.remote_control = true;
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
        settings = {
          provider = {
            gpu-vm-vllm = {
              name = "GPU VM vLLM (wiit-edge-002 2×A100)";
              npm = "@ai-sdk/openai-compatible";
              api = "http://localhost:8000/v1";
              models = {
                "Qwen/Qwen2.5-Coder-32B-Instruct" = {
                  id = "Qwen/Qwen2.5-Coder-32B-Instruct";
                  name = "Qwen2.5-Coder-32B-Instruct (vLLM)";
                  tool_call = true;
                  attachment = false;
                  reasoning = false;
                };
              };
            };
          };
        };
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
  };
}
