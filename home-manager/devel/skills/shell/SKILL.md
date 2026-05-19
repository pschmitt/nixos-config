---
name: shell
description: Use when writing, editing, reviewing, or generating shell code in bash, sh, or zsh. Applies to scripts, sourced shell files, functions, and shell snippets. Enforces the repo shell style and safe entrypoint/error-handling patterns.
---

# Shell

Use this skill for bash, sh, and zsh work.

## Scope

- Apply to executable scripts, sourced shell files, plugin files, shell functions, and inline shell snippets.
- Prefer bash unless the target file is explicitly zsh-specific or already uses another shell.

## Core rules

- Use `#!/usr/bin/env bash` for executable bash scripts.
- Ensure shell code passes `shellcheck`.
- Add a vim modeline at the bottom for 2-space indentation.
- Use 2-space indentation. Do not mix tabs and spaces.
- Put `then`, `do`, `elif`, `else`, and similar control-structure keywords on their own lines.
- Do not use semicolon-packed conditionals or loops.
- Use `[[ ... ]]` instead of `[ ... ]`.
- Define functions as `name() { ... }`.
- Keep functions focused on one responsibility.
- Do not `exit` from functions. Use `return`; only the main block should `exit`.
- Prefer functions plus a `main()` entrypoint guarded with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` so scripts can be sourced safely.
- Put every statement on its own line.

## Arguments and usage

- Put `usage()` first in interactive scripts.
- Support `-h|--help`.
- Do not hardcode the script name in help text; use `$(basename "$0")`.
- For invalid arguments, print usage to stderr.
- Prefer a simple `while`/`case` argument parser over `getopts` unless a more specific local convention overrides this.

## Errors and booleans

- Print error messages to stderr.
- Return or exit with code `2` when required parameters are missing.
- Do not use `"true"` or `"false"` string booleans.
- Use `1` for true and unset or empty for false.

## Data flow

- Avoid useless `echo` pipelines. Prefer redirections and here-strings such as `bar <<< "foo"`.

## Reference pattern

```bash
#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") ACTION [OPTIONS]
EOF
}

run_action() {
  :
}

main() {
  local debug

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --debug)
        debug=1
        shift
        ;;
      --trace)
        set -x
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -z "${1:-}" ]]
  then
    printf 'Missing action\n' >&2
    usage >&2
    return 2
  fi

  run_action "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
```
