#!/usr/bin/env bash

# Collect the raw material for a skill-suggestions review: what the user asked
# recently, where they corrected the agents, which skills and commands the
# agents used. Writes plain files to an output directory; the analysis is the
# agent's job (see SKILL.md).

CLAUDE_DIRS=("$HOME/.config/claude" "$HOME/.config/claude-work" "$HOME/.config/claude-auto")
CODEX_DIR="$HOME/.config/codex"
AGY_DB="$HOME/.gemini/antigravity-cli/conversation_summaries.db"

CORRECTION_RE="again|still|nope|wrong|why did|not working|doesn.t work|broken|i told you|already|forgot|didn.t|should have|always|never|dang it|erm "

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Collect recent prompts, corrections and tool usage of claude, claude-work,
claude-auto, codex and agy into an output directory.

Options:
  --days N     Look back N days (default: 14)
  --out DIR    Output directory (default: ./skill-suggestions-data)
  -h, --help   Show this help
EOF
}

claude_history() {
  local since_ms="$1" dir name

  for dir in "${CLAUDE_DIRS[@]}"
  do
    [[ -f "$dir/history.jsonl" ]] || continue
    name="$(basename "$dir")"
    jq -r --argjson s "$since_ms" --arg a "$name" '
      select(.timestamp >= $s)
      | [$a, (.timestamp / 1000 | strftime("%m-%d %H:%M")),
         (.project | split("/") | last),
         (.display | gsub("[\n\t]"; " ") | .[0:400])]
      | @tsv' "$dir/history.jsonl"
  done
}

codex_history() {
  local since_s="$1"

  [[ -f "$CODEX_DIR/history.jsonl" ]] || return 0
  jq -r --argjson s "$since_s" '
    select(.ts >= $s)
    | ["codex", (.ts | strftime("%m-%d %H:%M")), .session_id[0:8],
       (.text | gsub("[\n\t]"; " ") | .[0:400])]
    | @tsv' "$CODEX_DIR/history.jsonl"
}

agy_conversations() {
  local since_date="$1"

  [[ -f "$AGY_DB" ]] || return 0
  # 2-step conversations are usage probes ("say hi"), not work.
  sqlite3 -separator $'\t' "$AGY_DB" "
    select 'agy', strftime('%m-%d', last_modified_time), step_count,
           substr(replace(replace(title, char(9), ' '), char(10), ' '), 1, 120),
           substr(replace(replace(preview, char(9), ' '), char(10), ' '), 1, 300)
    from conversation_summaries
    where last_modified_time >= '$since_date' and step_count > 2
    order by last_modified_time"
}

claude_tool_use() {
  local days="$1" dir
  local -a files=()

  for dir in "${CLAUDE_DIRS[@]}"
  do
    [[ -d "$dir/projects" ]] || continue
    while IFS= read -r file
    do
      files+=("$file")
    done < <(timeout 120 find "$dir/projects" -name '*.jsonl' -mtime "-$days" -not -path '*/subagents/*')
  done

  [[ ${#files[@]} -gt 0 ]] || return 0
  jq -r 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use")
    | if .name == "Skill" then "SKILL\t" + (.input.skill // "")
      elif .name == "Bash" then "BASH\t" + ((.input.command // "") | gsub("\n"; " ") | .[0:160])
      else "TOOL\t" + .name end' "${files[@]}" 2>/dev/null
}

main() {
  local days=14 out="./skill-suggestions-data"

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --days)
        days="$2"
        shift 2
        ;;
      --out)
        out="$2"
        shift 2
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  mkdir -p "$out" || return 1

  local since_s since_ms since_date
  since_s="$(date -d "-$days days" +%s)"
  since_ms=$((since_s * 1000))
  since_date="$(date -d "-$days days" +%Y-%m-%d)"

  {
    claude_history "$since_ms"
    codex_history "$since_s"
  } > "$out/prompts.tsv"
  agy_conversations "$since_date" > "$out/agy.tsv"

  rg -i "$CORRECTION_RE" "$out/prompts.tsv" > "$out/corrections.tsv"

  claude_tool_use "$days" > "$out/tool-use.tsv"
  awk -F'\t' '$1 == "SKILL" { print $2 }' "$out/tool-use.tsv" | sort | uniq -c | sort -rn > "$out/skills-used.txt"
  awk -F'\t' '$1 == "BASH" { n = split($2, w, " "); print (n > 1 ? w[1] " " w[2] : w[1]) }' "$out/tool-use.tsv" \
    | sort | uniq -c | sort -rn | head -80 > "$out/bash-heads.txt"

  # Per-project and per-agent volume, to see where the time goes.
  awk -F'\t' '{ print $1 "\t" $3 }' "$out/prompts.tsv" | sort | uniq -c | sort -rn | head -40 > "$out/volume.txt"

  wc -l "$out"/*.tsv "$out"/*.txt
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
