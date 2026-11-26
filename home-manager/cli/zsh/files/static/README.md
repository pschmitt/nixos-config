# Static Zsh overrides

Put local functions and aliases in `*.zsh` files here. Zsh loads them in
filename order after the Home Manager plugins, so they can override managed
definitions. Reload them with `zsrclocal` or start a new shell.

Track these files with yadm to share them without rebuilding Nix:

```sh
yadm add ~/.config/zsh/static/my-overrides.zsh
```

This README is managed by Home Manager. Only `*.zsh` files are sourced.
