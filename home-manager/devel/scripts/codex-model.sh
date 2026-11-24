model_family=${1:?usage: codex-model FAMILY [--subagent-family FAMILY] [ARG...]}
shift

subagent_family=""
if [[ ${1:-} == --subagent-family ]]
then
  subagent_family=${2:?--subagent-family requires a family}
  shift 2
fi

cache="${CODEX_HOME:-$HOME/.config/codex}/models_cache.json"
resolve_model() {
  jq -er --arg family "$1" '
    [.models[] | select(.visibility == "list") | .slug
     | capture("^gpt-(?<major>[0-9]+)\\.(?<minor>[0-9]+)-(?<family>[a-z]+)$")
     | select(.family == $family)]
    | max_by([(.major | tonumber), (.minor | tonumber)])
    | "gpt-\(.major).\(.minor)-\(.family)"
  ' "$cache"
}

model=$(resolve_model "$model_family") || {
  printf 'No available Codex model found for %s in %s\n' "$model_family" "$cache" >&2
  exit 1
}
effort=$(jq -er --arg model "$model" '
  .models[] | select(.slug == $model) | .default_reasoning_level // empty
' "$cache") || {
  printf 'No default reasoning effort found for %s\n' "$model" >&2
  exit 1
}

args=( -m "$model" -c "model_reasoning_effort=$effort" )
if [[ -n $subagent_family ]]
then
  subagent_model=$(resolve_model "$subagent_family") || {
    printf 'No available Codex model found for %s in %s\n' "$subagent_family" "$cache" >&2
    exit 1
  }
  args+=( -c "agents.default_subagent_model=$subagent_model" )
fi

exec codex "${args[@]}" "$@"
