# CodexBar CLI — AI plan/quota reporting for Codex, the OpenAI admin API,
# Claude and Antigravity. Feeds the salemsayed/codexbar-meter Noctalia widget
# (profiles/laptop/noctalia.nix) and is useful on its own in a terminal.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.codexbar;

  configFile = (pkgs.formats.json { }).generate "codexbar-config.json" {
    version = 1;
    # Only the providers we actually use. Everything CodexBar knows about
    # defaults to disabled, so the other ~65 entries are noise.
    #
    # No credentials live in here: the OpenAI admin key comes from sops via
    # OPENAI_ADMIN_KEY in the wrapper below, and Codex/Claude/Antigravity are
    # read by CodexBar straight out of their own CLIs' credential stores.
    providers =
      map
        (id: {
          inherit id;
          enabled = true;
        })
        [
          "codex"
          "openai"
          "claude"
          "antigravity"
        ];
  };

  # CodexBar reports exactly one Claude account, and neither of its
  # multi-account mechanisms is usable here: `tokenAccounts` is rejected for
  # every provider but zai ("Token-account options are only supported for
  # --provider zai"), and claude-swap reads the macOS Keychain. What does work
  # is CODEXBAR_CLAUDE_OAUTH_TOKEN together with `--source oauth`, so the
  # wrapper re-runs the Claude provider once per account and tags each result
  # with the account label. codexbar-meter's providerLabel() renders that as
  # "Claude · private" / "Claude · work" while keeping the Claude icon.
  wrapper = pkgs.writeShellApplication {
    name = "codexbar";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      readonly CODEXBAR="${pkgs.codexbar}/bin/CodexBarCLI"
      readonly OPENAI_ADMIN_KEY_FILE="${cfg.openaiAdminKeyFile}"

      export_openai_admin_key() {
        if [[ ! -r "$OPENAI_ADMIN_KEY_FILE" ]]
        then
          return 0
        fi

        OPENAI_ADMIN_KEY="$(< "$OPENAI_ADMIN_KEY_FILE")"
        export OPENAI_ADMIN_KEY
      }

      # Emit the Claude provider's usage for one account, tagged so the bar can
      # tell the accounts apart. A missing or tokenless credentials file is not
      # an error: the account simply does not exist on this host.
      #
      # CodexBar exits non-zero for an unauthorized provider (3 on an expired
      # OAuth token) while still printing the error as JSON, so failures are
      # swallowed here rather than allowed to trip errexit — one stale token
      # must cost its own card, not everybody else's.
      claude_account() {
        local label="$1"
        local creds="$2"
        local token
        local usage

        if [[ ! -r "$creds" ]]
        then
          return 0
        fi

        token="$(jq -r '.claudeAiOauth.accessToken // empty' "$creds")" || return 0
        if [[ -z "$token" ]]
        then
          return 0
        fi

        usage="$(
          CODEXBAR_CLAUDE_OAUTH_TOKEN="$token" \
            "$CODEXBAR" usage --provider claude --source oauth --format json --json-only
        )" || true
        if [[ -z "$usage" ]]
        then
          return 0
        fi

        jq --arg account "$label" 'map(.account = $account)' <<< "$usage" || true
      }

      # True only for the all-providers JSON `usage` call that the Noctalia
      # widget makes. Anything else (text output, an explicit --provider, any
      # other subcommand) is none of our business and goes straight through.
      wants_merged_usage() {
        if [[ "''${1:-}" != usage ]]
        then
          return 1
        fi

        case " $* " in
          *" --provider "*)
            return 1
            ;;
        esac

        case " $* " in
          *" --json "*|*" --json-only "*|*" json "*)
            return 0
            ;;
        esac

        return 1
      }

      merged_usage() {
        local tmp
        local -a parts

        tmp="$(mktemp --directory)"
        # shellcheck disable=SC2064 # $tmp must expand now, not on trap
        trap "rm -rf '$tmp'" EXIT

        # CodexBar's own single-account Claude card is dropped in favour of the
        # per-account ones appended below.
        "$CODEXBAR" "$@" |
          jq 'map(select(.provider != "claude"))' > "$tmp/base.json"
        parts=("$tmp/base.json")

        ${lib.concatStringsSep "\n  " (
          lib.concatMap (label: [
            ''claude_account ${lib.escapeShellArg label} ${
              lib.escapeShellArg cfg.claudeAccounts.${label}
            } > "$tmp/claude-${label}.json"''
            ''parts+=("$tmp/claude-${label}.json")''
          ]) (lib.attrNames cfg.claudeAccounts)
        )}

        # Files left empty by a skipped account contribute no inputs to --slurp.
        jq --slurp 'add // []' "''${parts[@]}"
      }

      main() {
        export_openai_admin_key

        if wants_merged_usage "$@"
        then
          merged_usage "$@"
          return $?
        fi

        exec "$CODEXBAR" "$@"
      }

      if [[ "''${BASH_SOURCE[0]}" == "''${0}" ]]
      then
        main "$@"
      fi

      # vim: set ft=sh et ts=2 sw=2 :
    '';
  };
in
{
  options.custom.codexbar = {
    enable = lib.mkEnableOption "the CodexBar AI usage CLI" // {
      default = true;
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = wrapper;
      defaultText = lib.literalMD "a `codexbar` wrapper around `pkgs.codexbar`";
      description = ''
        The `codexbar` wrapper to put on PATH and to point CodexBar consumers
        (such as the codexbar-meter Noctalia plugin's `codexbarPath`) at. It
        injects the OpenAI admin key from sops and reports every Claude account
        in {option}`custom.codexbar.claudeAccounts` instead of just one.
      '';
    };

    claudeAccounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        private = "${config.home.homeDirectory}/.claude/.credentials.json";
        work = "${config.xdg.configHome}/claude-work/.credentials.json";
      };
      defaultText = lib.literalMD "the `claude` and `claude-work` credential stores";
      description = ''
        Claude accounts to report usage for, as label -> path of the Claude
        Code `.credentials.json` holding that account's OAuth token. Accounts
        whose file is absent are skipped, so the same set works on hosts that
        only have one of them. Labels are shown in the bar next to the provider
        name and are sorted alphabetically.
      '';
    };

    openaiAdminKeyFile = lib.mkOption {
      type = lib.types.str;
      default = config.sops.secrets."openai/admin_key".path;
      defaultText = lib.literalMD "the `openai/admin_key` sops secret";
      description = ''
        File holding the OpenAI admin API key (`sk-admin-…`) that the `openai`
        provider needs to read the usage/costs admin API. Passed to CodexBar as
        OPENAI_ADMIN_KEY so it never lands in the config file or the store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."openai/admin_key" = {
      mode = "0400";
      sopsFile = ../../secrets/shared.sops.yaml;
    };

    # CodexBar persists its own Settings toggles here, so a read-only store
    # symlink means `codexbar config enable/disable` can no longer write. That
    # is the point: provider enablement is declared above.
    xdg.configFile."codexbar/config.json".source = configFile;

    home.packages = [ cfg.package ];
  };
}
