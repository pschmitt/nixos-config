# Static Zsh overrides

Put local functions and aliases in `*.zsh` files here. Zsh loads them in
filename order after the Home Manager plugins, so they can override managed
definitions. Reload them with `zsrclocal` or start a new shell.

To share them between hosts without rebuilding Nix, track them with yadm:

```sh
yadm add ~/.config/zsh/static/my-overrides.zsh
```

This README is managed by Home Manager. Only `*.zsh` files are sourced.
