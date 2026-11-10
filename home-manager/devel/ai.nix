{
  config,
  lib,
  pkgs,
  ...
}:
let
  domainName = config.domains.main;
  # Keep the proxy on the stable Python set: unstable mcp-proxy requires MCP
  # 1.27.1, while unstable currently ships MCP 2.x.
  mcpProxy = pkgs.stable.mcp-proxy;
  browserHosts = [
    "fnuc"
    "rofl-13"
    "rofl-14"
    "rofl-15"
    "rofl-16"
  ];

  browserNode = host: "https://browser.${host}.${config.domains.netbird}";

  # Starts the Playwright MCP and tells the node which agent connects (agent,
  # conversation, project), shown on the node's dashboard.
  browserMcp = pkgs.writeShellApplication {
    name = "browser-mcp";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.playwright-mcp
    ];
    text = builtins.readFile ./scripts/browser-mcp.sh;
  };

  # Card rules stay in a user-owned runtime file, outside the Nix store.
  browserDaemonMcp = pkgs.writeShellApplication {
    name = "browser-daemon-mcp";
    runtimeInputs = [
      pkgs.browser-daemon
      pkgs.jq
    ];
    text = ''
      api_config="''${XDG_CONFIG_HOME:-$HOME/.config}/browser-daemon/rbw-api.json"
      api_url="$(jq -er '.url' "$api_config")"
      api_ca="$(jq -er '.ca' "$api_config")"
      set -- "$@" --rbw-api-url "$api_url" --rbw-api-ca "$api_ca"
      mapfile -t api_certs < <(jq -er '.clients[].cert' "$api_config")
      mapfile -t api_keys < <(jq -er '.clients[].key' "$api_config")
      if (( ''${#api_certs[@]} == 0 || ''${#api_certs[@]} != ''${#api_keys[@]} ))
      then
        printf '%s\n' 'RBW API client certificate/key configuration is incomplete' >&2
        exit 1
      fi
      for cert in "''${api_certs[@]}"
      do
        set -- "$@" --rbw-api-cert "$cert"
      done
      for key in "''${api_keys[@]}"
      do
        set -- "$@" --rbw-api-key "$key"
      done
      card_rules="''${XDG_CONFIG_HOME:-$HOME/.config}/browser-daemon/card-allowlist"
      if [[ -r "$card_rules" ]]
      then
        while IFS= read -r rule || [[ -n "$rule" ]]
        do
          [[ -z "$rule" || "$rule" == \#* ]] && continue
          set -- "$@" --allow-card "$rule"
        done < "$card_rules"
      fi
      exec browser-daemon "$@"
    '';
  };

  # Labels this agent conversation's browser sessions with a topic.
  browserAgentTopic = pkgs.writeShellApplication {
    name = "browser-agent-topic";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    runtimeEnv.BROWSER_AGENT_NODES = lib.concatMapStringsSep " " browserNode browserHosts;
    text = builtins.readFile ./scripts/browser-agent-topic.sh;
  };

  claudeStatusline = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
    ];
    runtimeEnv = {
      CLAUDE_STATUSLINE_JQ = "${./scripts/claude-statusline.jq}";
      CLAUDE_STATUSLINE_PERSONAL_EMAIL = config.mainUser.email.personal;
      CLAUDE_STATUSLINE_WORK_EMAIL = config.mainUser.email.work;
    };
    text = builtins.readFile ./scripts/claude-statusline.sh;
  };

  # SessionStart hook: names the agent's tmux window after the project dir.
  claudeTmuxRename = pkgs.writeShellApplication {
    name = "claude-tmux-rename";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.tmux
    ];
    text = builtins.readFile ./scripts/claude-tmux-rename.sh;
  };

  # Claude Code and Codex behind two secret filters before anything reaches
  # the provider: og-local (ML detector, placeholders for PII and shapeless
  # secrets) and Secretgate (regexes for key and token formats). Opt-in: plain
  # `claude` and `codex` are unchanged. See the secret-hygiene skill.
  oglSecretgate = pkgs.writeShellApplication {
    name = "ogl-secretgate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.og-local
      pkgs.secretgate
    ];
    text = builtins.readFile ./scripts/ogl-secretgate.sh;
  };

  claudeOgl = pkgs.writeShellApplication {
    name = "claude-ogl";
    runtimeInputs = [ oglSecretgate ];
    text = ''
      exec ogl-secretgate claude "$@"
    '';
  };

  codexOgl = pkgs.writeShellApplication {
    name = "codex-ogl";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.og-local
      oglSecretgate
    ];
    text = builtins.readFile ./scripts/codex-ogl.sh;
  };

  agentTmuxContextHook = pkgs.agent-tmux-context-hook;
  # PreToolUse/PostToolUse hooks that keep credentials out of tool calls and
  # results (see the leaked-credentials skill); Codex gets them too via
  # modules/codex-managed-hooks.nix.
  agentSecretGuard = pkgs.agent-secret-guard;
  agentSecretScan = pkgs.agent-secret-scan;

  # agy refuses clipboard image paste whenever an SSH session is detected
  # (`SSH_CLIENT`, `SSH_TTY`, or `SSH_CONNECTION` is non-empty, unless the
  # terminal is iTerm2), aborting with "Image upload is not supported in this
  # terminal" before checking the local clipboard. Even without that check,
  # agy's `hasDisplayClipboard` / `ReadClipboardMedia` only uses `wl-paste`
  # when `WAYLAND_DISPLAY` is set and otherwise requires both `DISPLAY` and
  # `xclip` on `PATH`. Unset the SSH variables and default `WAYLAND_DISPLAY`
  # to the headless `ssh-clipboard` compositor so image pasting works over SSH
  # via `ssh-clipboard`.
  antigravityCli = pkgs.symlinkJoin {
    name = "antigravity-cli-wrapped";
    paths = [ pkgs.llm-agents.antigravity-cli ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/agy \
        --unset SSH_CLIENT \
        --unset SSH_TTY \
        --unset SSH_CONNECTION \
        --set-default WAYLAND_DISPLAY wayland-ssh-clipboard
    '';
    meta.mainProgram = "agy";
  };

  # Sends Signal messages through the signal-cli daemon of the Hermes gateway
  # (services/hermes.nix), which is reachable over the mesh only.
  signalMcp = pkgs.writers.writePython3Bin "signal-mcp" {
    libraries = [ pkgs.python3Packages.mcp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/signal-mcp.py);

  # Ad-hoc build workers as MCP tools (up/ls/exec/start/logs/sync/down),
  # on top of the rworker client so host keys and state are shared.
  rworkerMcp = pkgs.writers.writePython3Bin "rworker-mcp" {
    libraries = [ pkgs.python3Packages.mcp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/rworker-mcp.py);

  # One browser MCP for every node and profile: `browser-daemon mcp` runs Playwright
  # MCP on a browser-daemon node, a throwaway browser on the node with the most room
  # unless the agent asks otherwise (`browser_use`). Profiles keep their logins;
  # agents may open the ones allowed here (`*`: all of them): `work` is signed in
  # to Microsoft (Outlook) and OpsGenie, `home-assistant` to Home Assistant (ha.brkn.lol, for
  # dashboard checks; see the HA repo's AGENTS.md), `hrworks` to HR WORKS,
  # `google-pschmitt` and `google` to two of Philipp's Google accounts (`google`
  # is the one Frigate+ and other "Sign in with Google" sites use).
  # browser_fill_secret types the rbw entries named with `--allow-secret` (`*`:
  # every entry) into login forms on their own sites without the agent seeing
  # the value. browser_passkey has the nodes' secret agent sign passkey
  # sign-ins on the `--allow-passkey` sites (`*`: every site; mind
  # auth.brkn.lol, whose Authelia flags the Bitwarden client as a clone once the
  # vault counter moves on, skills/browser-login/references/counters.md). browser_ask_human sends the
  # user a live-view link of the agent's page (the browser-login skill's
  # ask-human.sh). browser_export_auth and browser_fetch hand a page's login
  # (cookies, storage tokens) to other tools without the agent seeing it; every
  # site for now (`--allow-export`).
  browserAskHuman = pkgs.writeShellApplication {
    name = "browser-ask-human";
    runtimeInputs = [
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
      pkgs.rbw
      pkgs.zsh
    ];
    text = builtins.readFile ./skills/browser-login/scripts/ask-human.sh;
  };
  # Ad-hoc build workers on OpenStack (skills/rworker): talks to the
  # control host over SSH, pins each worker's host key locally.
  rworker = pkgs.symlinkJoin {
    name = "rworker";
    meta.mainProgram = "rworker";
    paths = [
      (pkgs.writeShellApplication {
        name = "rworker";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.jq
          pkgs.openssh
          pkgs.rsync
          pkgs.util-linux
        ];
        text = builtins.readFile ./skills/rworker/scripts/rworker.sh;
      })
      # zsh and bash completions; Home Manager links them into the profile.
      (pkgs.runCommand "rworker-completions" { } ''
        install -Dm644 ${./skills/rworker/completions/_rworker} $out/share/zsh/site-functions/_rworker
        install -Dm644 ${./skills/rworker/completions/rworker.bash} $out/share/bash-completion/completions/rworker
      '')
    ];
  };
  browserMcps.browser-daemon = {
    command = lib.getExe browserDaemonMcp;
    env.XDG_RUNTIME_DIR = "/run/user/${toString config.host.uid}";
    args = [
      "mcp"
      "--url"
      (browserNode "rofl-14")
      "--playwright-cmd"
      (lib.getExe browserMcp)
      "--output-dir"
      "${config.xdg.cacheHome}/playwright-mcp/browser"
      "--allow-profile"
      "*"
      "--allow-secret"
      "*"
      "--allow-passkey"
      "*"
      "--ask-human-cmd"
      (lib.getExe browserAskHuman)
      "--allow-export"
      "*"
    ];
  };

  upstreamSkills = import ./upstream-skills.nix {
    inherit (pkgs) fetchFromGitHub todoist-cli;
    inherit (pkgs.llm-agents) terminal-browser;
  };

  # Keep the skill-improvement instruction in one file and add it to our
  # public and private skills while assembling the shared skill tree. CKS
  # skills carry their own guidance from git.wiit.one.
  withSkillImprovementFooter =
    source:
    pkgs.runCommand "skills-with-improvement-footer" { } ''
      mkdir -p "$out"
      cp -rL ${source}/. "$out"/
      chmod -R u+w "$out"
      for skill_dir in "$out"/*; do
        [ -d "$skill_dir" ] || continue
        skill_name="''${skill_dir##*/}"
        case "$skill_name" in
          cks-*) continue ;;
        esac
        skill_file="$skill_dir/SKILL.md"
        [ -f "$skill_file" ] || continue
        cat ${./skill-footer.md} >> "$skill_file"
      done
    '';

  skillSources = [
    (withSkillImprovementFooter ./skills)
  ]
  ++ upstreamSkills
  ++ map withSkillImprovementFooter config.dotfiles.aiSkills.extraSources;

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
  # A skill folder in several sources is merged like symlinkJoin does it: the
  # first source wins per file (store copies are read-only, hence the chmod).
  codexSkills = toString (
    pkgs.runCommand "codex-skills" { } ''
      mkdir -p "$out"
      ${lib.concatMapStringsSep "\n" (
        path: "cp -rLn ${path}/. \"$out\"/ && chmod -R u+w \"$out\""
      ) skillSources}
      # Upstream skill collections include root-level README indexes. Codex
      # treats files in the skills root as skill candidates and warns when
      # those indexes lack the SKILL.md frontmatter.
      rm -f "$out/README.md"
    ''
  );

  # Remote (streamable-HTTP) MCP server reached through mcp-proxy. It trusts
  # SSL_CERT_FILE when set (claude-ogl/codex-ogl route traffic through
  # Secretgate's TLS interception and point it at that CA). The bearer
  # token is injected via `env.API_ACCESS_TOKEN.file`: home-manager's MCP module
  # generates a wrapper that reads the sops secret at startup (see
  # lib.hm.mcp.wrapEnvFilesCommand), so no hand-rolled token-reading script is
  # needed.
  mcpHttpProxy =
    {
      url,
      tokenFile,
    }:
    let
      proxy = pkgs.writeShellApplication {
        name = "mcp-http-proxy-${builtins.substring 0 8 (builtins.hashString "sha256" url)}";
        text = ''
          exec ${mcpProxy}/bin/mcp-proxy \
            --transport streamablehttp \
            --verify-ssl "''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}" \
            ${lib.escapeShellArg url}
        '';
      };
    in
    {
      command = lib.getExe proxy;
      env.API_ACCESS_TOKEN.file = tokenFile;
    };

  # TREK uses OAuth client credentials for unattended MCP clients. Keep the
  # client credentials in SOPS and read them only when the proxy starts.
  mcpOAuthProxy =
    {
      url,
      tokenUrl,
      clientIdFile,
      clientSecretFile,
    }:
    let
      proxy = pkgs.writeShellApplication {
        name = "mcp-trek";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          client_id=$(<${lib.escapeShellArg clientIdFile})
          client_secret=$(<${lib.escapeShellArg clientSecretFile})
          access_token=$(curl --fail-with-body --silent --show-error \
            --data-urlencode grant_type=client_credentials \
            --data-urlencode client_id="$client_id" \
            --data-urlencode client_secret="$client_secret" \
            ${lib.escapeShellArg tokenUrl} | jq --exit-status --raw-output .access_token)
          API_ACCESS_TOKEN="$access_token" exec ${mcpProxy}/bin/mcp-proxy \
            --transport streamablehttp \
            --verify-ssl "''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}" \
            ${lib.escapeShellArg url}
        '';
      };
    in
    {
      command = lib.getExe proxy;
    };

  # Google Workspace MCP (taylorwilsdon/google_workspace_mcp): Gmail incl.
  # sending. Its fastmcp dependency is broken in nixpkgs, so it runs from PyPI
  # through uv at a pinned version. It normally does its own browser consent;
  # the wrapper instead seeds its credential store from the refresh token we
  # already hold (in SOPS) and starts it in single-user mode.
  mcpWorkspace =
    {
      version,
      tools,
      clientIdFile,
      clientSecretFile,
      refreshTokenFile,
      scopes,
    }:
    let
      wrapper = pkgs.writeShellApplication {
        name = "workspace-mcp-wrapper";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
          pkgs.uv
        ];
        text = ''
          client_id=$(<${lib.escapeShellArg clientIdFile})
          client_secret=$(<${lib.escapeShellArg clientSecretFile})
          refresh_token=$(<${lib.escapeShellArg refreshTokenFile})
          access_token=$(curl --fail-with-body --silent --show-error \
            --data-urlencode grant_type=refresh_token \
            --data-urlencode client_id="$client_id" \
            --data-urlencode client_secret="$client_secret" \
            --data-urlencode refresh_token="$refresh_token" \
            https://oauth2.googleapis.com/token | jq --exit-status --raw-output .access_token)
          email=$(curl --fail-with-body --silent --show-error \
            --header "Authorization: Bearer $access_token" \
            https://gmail.googleapis.com/gmail/v1/users/me/profile \
            | jq --exit-status --raw-output .emailAddress)

          creds_dir="''${XDG_RUNTIME_DIR:-/tmp}/workspace-mcp-$(id -u)/credentials"
          mkdir -p "$creds_dir"
          chmod 700 "$creds_dir"
          (
            umask 077
            jq --null-input \
              --arg client_id "$client_id" \
              --arg client_secret "$client_secret" \
              --arg refresh_token "$refresh_token" \
              --argjson scopes ${lib.escapeShellArg (builtins.toJSON scopes)} \
              '{token: null, refresh_token: $refresh_token,
                token_uri: "https://oauth2.googleapis.com/token",
                client_id: $client_id, client_secret: $client_secret,
                scopes: $scopes, expiry: null}' \
              > "$creds_dir/$email.json"
          )

          export WORKSPACE_MCP_CREDENTIALS_DIR="$creds_dir"
          export USER_GOOGLE_EMAIL="$email"
          export GOOGLE_OAUTH_CLIENT_ID="$client_id"
          export GOOGLE_OAUTH_CLIENT_SECRET="$client_secret"
          export OAUTHLIB_INSECURE_TRANSPORT=1
          exec uvx --python ${lib.getExe pkgs.python3} \
            --from ${lib.escapeShellArg "workspace-mcp==${version}"} workspace-mcp \
            --single-user --tools ${lib.escapeShellArgs tools}
        '';
      };
    in
    {
      command = lib.getExe wrapper;
    };

  # The Teams MCP and its `msteams` CLI sign in with the Teams login of the
  # work profile of a browser-daemon node instead of opening a local browser,
  # so they also work without a display.
  msteamsMcp = pkgs.msteams-mcp.overrideAttrs (old: {
    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--set-default"
      "TEAMS_MCP_BROWSER_DAEMON_URL"
      (browserNode "rofl-14")
    ];
  });

  # Outlook MCP signs in with the Outlook session of a browser-daemon profile,
  # matching the Teams MCP without starting a local browser or exposing tokens.
  msoutlookMcp = pkgs.msoutlook-mcp.overrideAttrs (old: {
    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--set-default"
      "MSOUTLOOK_BROWSER_DAEMON_URL"
      (browserNode "rofl-14")
      "--set-default"
      "MSOUTLOOK_BROWSER_DAEMON_PROFILE"
      "work"
    ];
  });
in
{
  options.dotfiles.aiSkills.extraSources = lib.mkOption {
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
          Define `domains.main` in the NixOS host configuration.
        '';
      }
    ];

    sops = {
      secrets = {
        "mistral-vibe/env" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        "n8n/mcp/token" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        # Bichon (email archive) API access token, read-only lookups.
        "bichon/mcp/token" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        # Own Google Cloud OAuth client (project "Gmail MCP") and the refresh
        # token from its one-time consent, for the Google Workspace MCP server.
        "gmail/mcp/client-id" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        "gmail/mcp/client-secret" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        "gmail/mcp/refresh-token" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        "trek/mcp/client-id" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        "trek/mcp/client-secret" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        # GEC Slack workspace user token (xoxp-...), lets the Slack MCP server
        # read/post as Philipp's own Slack identity rather than a bot user.
        "slack/gec-chat/xoxp-token" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        # The user's own number, behind the `me` recipient of the signal MCP.
        "signal/me" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        # The bot account's own number, behind `self` (quote or react to its
        # own messages).
        "signal/self" = {
          mode = "0600";
          sopsFile = config.host.sopsDefaultFile;
        };
        # MCP uses the same host-specific Philipp Schmitt PAT:
        # `nixos-config (<HOSTNAME>)`.
        "home-assistant/token" = {
          mode = "0600";
          sopsFile = config.host.sopsFile;
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
          tokenFile = config.sops.secrets."home-assistant/token".path;
        };
        bichon = {
          command = lib.getExe pkgs.bichon-mcp;
          env = {
            BICHON_ACCESS_TOKEN.file = config.sops.secrets."bichon/mcp/token".path;
            BICHON_BASE_URL = "https://bichon.${domainName}";
          };
        };
        trek = mcpOAuthProxy {
          url = "https://trek.${domainName}/mcp";
          tokenUrl = "https://trek.${domainName}/oauth/token";
          clientIdFile = config.sops.secrets."trek/mcp/client-id".path;
          clientSecretFile = config.sops.secrets."trek/mcp/client-secret".path;
        };
        # Hosted Sentry MCP (sentry.io). It signs in with OAuth, which the
        # clients handle themselves (Claude Code: /mcp -> sentry -> Authenticate),
        # so it is a plain remote server rather than an mcp-proxy with a token.
        sentry.url = "https://mcp.sentry.dev/mcp";
        # Google Workspace MCP (Gmail, incl. send).
        google-workspace = mcpWorkspace {
          version = "2.3.0";
          tools = [
            "gmail"
            "calendar"
          ];
          scopes = [
            "openid"
            "https://www.googleapis.com/auth/userinfo.email"
            "https://www.googleapis.com/auth/userinfo.profile"
            "https://www.googleapis.com/auth/gmail.readonly"
            "https://www.googleapis.com/auth/gmail.modify"
            "https://www.googleapis.com/auth/gmail.compose"
            "https://www.googleapis.com/auth/gmail.send"
            "https://www.googleapis.com/auth/gmail.labels"
            "https://www.googleapis.com/auth/gmail.settings.basic"
            "https://www.googleapis.com/auth/calendar"
          ];
          clientIdFile = config.sops.secrets."gmail/mcp/client-id".path;
          clientSecretFile = config.sops.secrets."gmail/mcp/client-secret".path;
          refreshTokenFile = config.sops.secrets."gmail/mcp/refresh-token".path;
        };
        obsidian = {
          command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
          args = [ "${config.xdg.userDirs.documents}/notes" ];
        };
        concord.command = lib.getExe' pkgs.concord-mcp "concord-mcp";
        tmux = {
          command = lib.getExe pkgs.tmux-mcp-compat;
          args = [ "${pkgs.tmux-mcp}/bin/tmux-mcp-rs" ];
        };
        signal = {
          command = lib.getExe signalMcp;
          args = [
            "--url"
            "http://rofl-10.${config.domains.netbird}:8712"
            "--recipient"
            "me=${config.sops.secrets."signal/me".path}"
            "--recipient"
            "self=${config.sops.secrets."signal/self".path}"
          ];
        };
        slack = {
          command = "${pkgs.slack-mcp-server}/bin/slack-mcp-server";
          env = {
            SLACK_MCP_XOXP_TOKEN.file = config.sops.secrets."slack/gec-chat/xoxp-token".path;
            SLACK_MCP_ADD_MESSAGE_TOOL = "true";
          };
        };
        msteams.command = lib.getExe msteamsMcp;
        rworker = {
          command = lib.getExe rworkerMcp;
          args = [
            "--rworker"
            (lib.getExe rworker)
          ];
        };
        outlook.command = lib.getExe msoutlookMcp;
        todoist = {
          command = lib.getExe pkgs.todoist-mcp;
          env.TODOIST_API_KEY.file = config.sops.secrets."todoist/api_token".path;
        };
      }
      // browserMcps;
    };

    # Claude Code tracks workspace trust per path in ~/.claude.json (no
    # settings.json knob), so pre-accept the trust dialog for $HOME.
    home.activation.claudeTrustHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_file="$HOME/.claude.json"
      if [[ -f "$config_file" ]]
      then
        tmp_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.XXXXXX")"
        ${pkgs.jq}/bin/jq --arg path "$HOME" \
          '.projects[$path] = ((.projects[$path] // {}) + { hasTrustDialogAccepted: true })' \
          "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file" \
          || rm -f "$tmp_file"
      fi
    '';

    programs = {
      claude-code = {
        enable = true;
        package = pkgs.llm-agents.claude-code;
        configDir = "${config.xdg.configHome}/claude";
        skills = allSkills;
        enableMcpIntegration = true;
        plugins = {
          codex = pkgs.codex-plugin-cc;
          concord-relay = "${pkgs.concord-mcp}/lib/concord-mcp/plugin/concord-relay";
        };
        settings = {
          skipDangerousModePermissionPrompt = true;
          theme = "dark";
          env = {
            CLAUDE_CODE_SUBAGENT_MODEL = "sonnet";
            CLAUDE_CODE_SUBAGENT_MODEL_FORCE = "1";
          };
          teammateDefaultModel = "sonnet";
          statusLine = {
            type = "command";
            command = lib.getExe claudeStatusline;
          };
          hooks = {
            SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = lib.getExe claudeTmuxRename;
                  }
                ];
              }
            ];
            PreToolUse = [
              {
                matcher = "Bash";
                hooks = [
                  {
                    type = "command";
                    command = lib.getExe agentSecretGuard;
                  }
                ];
              }
            ];
            PostToolUse = [
              {
                matcher = "*";
                hooks = [
                  {
                    type = "command";
                    command = lib.getExe agentSecretScan;
                  }
                ];
              }
            ];
          };
        };
        # Keep the tmux tools loaded up front: deferred (ToolSearch) tools were
        # skipped for the window rename. Overrides the shared server for Claude only.
        mcpServers.tmux = config.programs.mcp.servers.tmux // {
          alwaysLoad = true;
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
          model = "gpt-6-luna";
          model_reasoning_effort = "high";
          notice.model_migrations = {
            "gpt-5.4" = "gpt-5.5";
          };

          tui = {
            status_line = [
              "model-with-reasoning"
              "project-name"
              "thread-name"
            ];

            keymap = {
              global.open_external_editor = "ctrl-e";
              editor = {
                delete_backward = "backspace";
                delete_backward_word = [
                  "ctrl-backspace"
                  "ctrl-h"
                ];
                move_line_start = [ "home" ];
                move_line_end = [ "end" ];
              };
            };

            model_availability_nux = {
              "gpt-5.5" = 4;
            };
          };

          projects = {
            "/etc/nixos".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/ansible-stuff.git".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/browser-daemon.git".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/bruvtab.git".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/ci-workflows.git".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/home-assistant-apps.git".trust_level =
              "trusted";
            "/mnt/ha".trust_level = "trusted";
            "/mnt/turris".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/rbw.git".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/monarch.git".trust_level = "trusted";
            "${config.home.homeDirectory}".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git".trust_level = "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config-private.git".trust_level =
              "trusted";
            "${config.home.homeDirectory}/devel/private/pschmitt/stricknani.git".trust_level = "trusted";
          };

          sandbox_mode = "danger-full-access";
          # The Nixpkgs CLI package does not include the complete package layout
          # required by Codex's automatic daemon installer.
          features = {
            daemon_auto_start = false;
            remote_control = true;
          };
        };
      };

      antigravity-cli = {
        enable = true;
        package = antigravityCli;
        context.CONTEXT = ./CONTEXT.md;
        skills = allSkills;
        enableMcpIntegration = true;
        settings = {
          model = "Gemini 3.8 Flash (Medium)";

          trustedWorkspaces = [
            "/etc/nixos"
            "/mnt/ha"
            "/home/pschmitt/devel/private/pschmitt/nixos-config.git"
          ];

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

          hooks.BeforeAgent = [
            {
              hooks = [
                {
                  name = "tmux-context";
                  type = "command";
                  command = lib.getExe agentTmuxContextHook;
                  timeout = 5000;
                }
              ];
            }
          ];

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
        # FIXME: Return to nixpkgs-unstable when its Copilot CLI binary works
        # on our build hosts; pinned master currently provides working 1.0.98.
        package = pkgs.master.github-copilot-cli;
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

    xdg.configFile."claude/keybindings.json".source = ./claude-keybindings.json;
    xdg.configFile."opencode/plugins/tmux-context.js".source = ./scripts/opencode-tmux-context.js;

    home = {
      # Concord reports usage telemetry (IP and country) unless told not to.
      sessionVariables.CONCORD_TELEMETRY_DISABLED = "1";

      # ctrl+backspace and ctrl+delete bound to chat:clearInput both failed to
      # register in practice, so that binding was dropped; only the ctrl+e
      # external-editor rebind remains in claude-keybindings.json.
      file = {
        ".gemini/antigravity-cli/keybindings.json" = {
          source = ./antigravity-keybindings.json;
          force = true;
        };
        ".gemini/antigravity-cli/settings.json".force = true;
      };

      # terminal-browser rewrites its own settings.json (`config set`), so merge
      # the declared keys in instead of symlinking a read-only file. "animation"
      # stops the image flicker when it renders through tmux.
      activation.terminalBrowserSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        config_file="${config.xdg.configHome}/terminal-browser/settings.json"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$config_file")"
        [[ -s "$config_file" ]] || echo '{}' > "$config_file"
        tmp_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.XXXXXX")"
        ${pkgs.jq}/bin/jq --argjson settings ${
          lib.escapeShellArg (builtins.toJSON { "render.presenter" = "animation"; })
        } '. + $settings' "$config_file" > "$tmp_file" \
          && mv "$tmp_file" "$config_file" || rm -f "$tmp_file"
      '';

      packages =
        with pkgs.llm-agents;
        [
          # vscode forks
          # antigravity
          # code-cursor

          # cli
          ccusage
          msteamsMcp
          terminal-browser
          pkgs.playwright-mcp
          # cursor-cli
          # kilocode-cli

          # FIXME vibe-cli is broken as of 2026-02-25
          # (pkgs.writeShellScriptBin "vibe" ''
          #   export VIBE_HOME="''${VIBE_HOME:-${config.xdg.configHome}/vibe}"
          #
          #   exec ${mistral-vibe}/bin/vibe "$@"
          # '')
        ]
        # Agents label their browser sessions with it (see CONTEXT.md).
        ++ [
          browserAgentTopic
          rworker
          claudeOgl
          claudeStatusline
          claudeTmuxRename
          codexOgl
          pkgs.concord-mcp
        ];
    };
  };
}
