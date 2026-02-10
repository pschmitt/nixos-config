# Shell Code Style Guide

The following applies to bash, sh and zsh.

## Basic Requirements

- **Shebang**: Use `#!/usr/bin/env bash` as the shebang
- **ShellCheck**: Ensure scripts always pass shellcheck
- **Vim modeline**: Add a vim modeline at the bottom to enforce 2-space indentation

## Style and Structure

### Indentation and Formatting

- **Indentation**: Use two spaces per indentation level. Do not mix tabs and spaces.
- **Statement formatting**: Put every statement on its own line (especially "then" and "do"):

```sh
# Bad
if xxx; then
  :
fi

while yyy; do
  :
done

# Good
if xxx
then
  :
fi

while yyy
do
  :
done
```

### Control Structures

- Place keywords on separate lines for `if`, `elif`, `else`, `for`, `while`, and `until` blocks
- Never combine multiple statements on one line with semicolons inside conditionals or loops
- Use `[[ test ]]` instead of `[ test ]`

### Functions

- Define functions with the `name() { ... }` form
- Avoid anonymous functions
- Keep function bodies focused on a single responsibility
- Never `exit` from functions - they should use `return`
- Only the main block should contain `exit` statements

### Entrypoint Pattern

Define a `main()` function and guard execution so the script can be sourced without side effects:

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

## Usage and Help

- **Usage function**: Place the usage function first in the script
- For interactive scripts, define a `usage()` function and support `-h|--help`
- Do not hardcode the script name or path in usage text; use `$(basename "$0")` (bash) instead
- Output usage to stderr for invalid arguments

## Error Handling

- Include proper error handling
- Print error messages to stderr
- Exit with code 2 when required parameters are missing

## Best Practices

- **Avoid useless echos**: Prefer `bar <<< "foo"` over `echo foo | bar`
- **Argument parsing**: Avoid using getopts, prefer a simple while loop over arguments
- Use functions extensively

## Variables and Booleans

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