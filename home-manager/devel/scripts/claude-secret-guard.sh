#!/usr/bin/env bash
# PreToolUse hook (Bash): refuse commands that routinely dump credentials into the
# transcript. Every pattern below caused a row in the leaked-credentials note.
# Exit 2 + stderr blocks the call and tells the agent what to do instead.

command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$command" ]] || exit 0

deny() {
  echo "Blocked (credentials would land in the transcript): $1" >&2
  exit 2
}

# Regexes live in variables: bash cannot parse a bare ( or | inside [[ =~ ]].
start='(^|[[:space:];|&(])'
readers='(cat|bat|less|more|head|tail|rg|grep|egrep|sed|awk|jq|yq|python3?|nl|strings|xxd)'
re_ha_store='(core\.config_entries|core\.restore_state|\.storage/auth|secrets\.ya?ml|frigate\.yaml\.bak)'
re_reader="${start}${readers}([[:space:]]|$)"
re_search="${start}(rg|grep|egrep)[[:space:]]"
re_mnt_ha='/mnt/ha(/\.storage)?([[:space:]]|$)'
re_ps="${start}ps[[:space:]]+(-?[a-zA-Z]*(aux|ef|axww|eww|auxww)|.*-o[[:space:]]*[a-z,]*(args|command|cmd))"
re_pgrep="${start}pgrep[[:space:]]+-[a-zA-Z]*[af][a-zA-Z]*([[:space:]]|$)"
re_proc='/proc/[^[:space:]]*/(cmdline|environ)'
re_envnames='(env|printenv)[[:space:]]*\|[[:space:]]*(cut|wc)[[:space:]]'
re_env='(^|[;&|(])[[:space:]]*(env|printenv|export|declare[[:space:]]+-x|set)[[:space:]]*([|;&]|$)'
re_rbw='rbw[[:space:]].*(--json|--raw)'
re_jqpipe='\|[[:space:]]*(jq|python3?)[[:space:]]'
re_redirect='>[[:space:]]*[^[:space:]&]'
re_gitdiff="${start}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(diff|show|log[[:space:]]+-p|stash[[:space:]]+show)"
re_sopspath='(sops|secrets|nixos-config-private|host_vars)'
re_osl='openstack[[:space:]].*(list|show)[[:space:]].*--long'
re_haapps="${start}ha[[:space:]]+(apps|addons)[[:space:]]+info"
re_hacheck="${start}ha[[:space:]]+core[[:space:]]+check"
re_ansible='(ansible-playbook|just[[:space:]]+(wrt|openwrt))[^|]*--diff'
re_trim='\|[[:space:]]*(tail|head|grep)'

# Home Assistant stores: whole entry lines carry passwords, OAuth tokens, API keys.
if [[ "$command" =~ $re_ha_store ]] &&
  [[ "$command" =~ $re_reader ]] &&
  [[ "$command" != *hass::config-entries* ]] &&
  [[ ! "$command" =~ ${start}sed[[:space:]]+(-[a-zA-Z]*i|--in-place) ]] &&
  [[ ! "$command" =~ $re_redirect ]]
then
  deny "use 'zsh -lc \"zhj hass::config-entries [--domain X]\"' for config entries; never read secrets.yaml or .storage/auth. To edit one value, use sed -i/jq with an in-place write and print nothing."
fi

# Broad searches over /mnt/ha pull the same files in.
if [[ "$command" =~ $re_search ]] &&
  [[ "$command" =~ $re_mnt_ha ]] &&
  [[ "$command" != *--glob* && "$command" != *--exclude* && "$command" != *-l* && "$command" != *--files-with-matches* ]]
then
  deny "searching /mnt/ha or /mnt/ha/.storage prints credential-bearing lines. Use 'rg -l' (file names only), exclude .storage and secrets.yaml via --glob '!...', or hass::config-entries."
fi

# Process listings with arguments: signed browser-daemon URLs, ustreamer --passwd, tokens.
if [[ "$command" =~ $re_ps ]] ||
  [[ "$command" =~ $re_pgrep ]] ||
  [[ "$command" =~ $re_proc ]]
then
  deny "process listings print command lines (signed URLs, --passwd, tokens). Use 'pgrep -l NAME', 'pgrep -c NAME' or 'ps -o pid,etime,comm -p PID'."
fi

# Whole-environment dumps.
if [[ "$command" =~ $re_env && ! "$command" =~ $re_envnames ]]
then
  deny "dumping the environment prints SOPS_AGE_KEY and tokens. Print the single variable you need, or 'env | cut -d= -f1' for names only."
fi

# rbw returning whole entries (passwords, TOTP seeds, passkeys, recovery codes).
if [[ "$command" =~ $re_rbw ]] &&
  [[ ! "$command" =~ (--redact|--mask|--no-secrets|RBW_REDACT) ]] &&
  [[ ! "$command" =~ $re_jqpipe ]] &&
  [[ ! "$command" =~ $re_redirect ]]
then
  deny "rbw --json/--raw prints the whole entry. Add --redact (rbw --redact get --json NAME), use the rbw MCP, 'rbw get --field NAME' into a variable, or pipe straight into jq with an explicit field selection."
fi

# Diffs of SOPS files go through the textconv driver and print plaintext.
if [[ "$command" =~ $re_gitdiff ]] &&
  [[ "$command" != *--no-textconv* && "$command" != *--stat* && "$command" != *--name-only* && "$command" != *--name-status* && "$command" != *--numstat* && "$command" != *--shortstat* && "$command" != *--check* ]] &&
  [[ "$command" =~ $re_sopspath || "$PWD" == *nixos-config-private* ]]
then
  deny "git diff/show on SOPS-backed paths decrypts via textconv. Add --no-textconv (or --stat/--name-only)."
fi

# Verbose CLIs that echo credentials.
if [[ "$command" =~ $re_osl ]]
then
  deny "'openstack ... --long' prints server properties incl. admin_pass. Select columns with -c."
fi
if [[ "$command" =~ $re_haapps ]]
then
  deny "'ha apps info' prints add-on options (passwords, UUIDs). Pipe through jq selecting named fields."
fi
if [[ "$command" =~ $re_hacheck ]]
then
  deny "'ha core check' expands the resolved config. Use 'zsh -lc \"zhj hass::check-config\"'."
fi
if [[ "$command" =~ $re_ansible ]] && [[ ! "$command" =~ $re_trim ]]
then
  deny "ansible --diff prints rendered templates with credentials. Drop --diff or pipe through grep for task names only."
fi

exit 0
