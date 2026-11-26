# jq
(( $+commands[jq] )) || return

alias jqz="jq::interactive"

zsh::autoload-dir jq

# Alternative implementation, without plib.jq
# Output the json paths for all objects (+ the value)
# https://news.ycombinator.com/item?id=20246957
# Sample output:
# .items[15].metadata.labels.kubernetes.io/arch = "amd64"
# .items[15].status.nodeInfo.operatingSystem = "linux"
# jqpaths() {
#   local with_values
#   zparseopts -D -K -E -values=with_values
#
#   local extra_jq_filter
#   if [[ -n "$with_values" ]]
#   then
#     extra_jq_filter='+ " = " + (.[1] | @json)'
#   fi
#
#   jq $@ -er --stream '
#     select(length > 1)
#     | (
#       .[0] | map(
#         if type == "number"
#         then "[" + tostring + "]"
#         else "." + .
#         end
#       ) | add
#     )'${extra_jq_filter}
# }

alias array-to-json="jq::array-to-json"
