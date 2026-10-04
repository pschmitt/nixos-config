# Lean single-line layout from the existing profile, with portable segments.
typeset -ga POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs context status prompt_char)
typeset -ga POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(command_execution_time background_jobs direnv virtualenv)
typeset -g POWERLEVEL9K_MODE=nerdfont-complete
typeset -g POWERLEVEL9K_BACKGROUND=
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=false
typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=' '
typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=' '
typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR=' '
typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR=' '
typeset -g POWERLEVEL9K_DIR_FOREGROUND=31
typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE="%F{${host_color:-red}}${host_alias:-%m}%f"
typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND="${host_color:-180}"
typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=196
typeset -g POWERLEVEL9K_STATUS_OK=false
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=same-dir
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

# vim: set ft=zsh et ts=2 sw=2 :
