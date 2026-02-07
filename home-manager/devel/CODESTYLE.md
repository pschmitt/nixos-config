## Shell code

The following applies to bash, sh and zsh.

### Style and Structure

- **Indentation**: Use two spaces per indentation level. Do not mix tabs and spaces.
- **Control structures**: Place keywords on separate lines—e.g. write `if condition` followed by `then` on the next line, and do
  the same for `elif`, `else`, `for`, `while`, and `until` blocks. Never combine multiple statements on one line with semicolons
  inside conditionals or loops.
- **Functions**: Define functions with the `name() { ... }` form. Avoid anonymous functions and keep function bodies focused on
  a single responsibility.
- **Entrypoint**: Define a `main()` function and guard execution so the script can be sourced without side effects. Prefer the
  same overall structure as `test.sh` (usage, optional actions, flag parsing, action dispatch):

```bash
#!/usr/bin/env bash

usage() {
  cat <<EOF
  Usage: $(basename "$0") ACTION [OPTIONS]

  Actions:
    action1    Description for action 1
    action2    Description for action 2
EOF
}

action1() {
  echo "Action 1 executed"
}

action2() {
  echo "Action 2 executed"
}

main() {
  local debug

  # global flags
  while [[ -n $* ]]
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

  local action="${1:-action1}" # default action

  case "$action" in
    action1|a1|1)
      [[ -n "${debug:-}" ]] && echo "Performing Action 1"
      action1
      ;;
    action2|a2|2)
      [[ -n "${debug:-}" ]] && echo "Performing Action 2"
      action2
      ;;
    *)
      echo "Unknown action: '$action'" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
```

- **Usage/help**: For interactive scripts, define a `usage()` function and support `-h|--help`. Do not hardcode the script name
  or path in usage text; use `$(basename "$0")` (bash) instead.
- **Booleans**: Do not use `"true"` and `"false"` string values for "bool" variables. Use `1` for true and unset/empty for false.

```sh
# Bad
ENABLE_FEATURE="true"
if [[ "$ENABLE_FEATURE" == "true" ]]
then
  do_the_thing
fi

# Good
ENABLE_FEATURE=1
if [[ -n "${ENABLE_FEATURE:-}" ]]
then
  do_the_thing
fi

# Also good for "false"
if [[ -z "${ENABLE_FEATURE:-}" ]]
then
  do_not_do_the_thing
fi
```
