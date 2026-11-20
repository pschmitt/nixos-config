#!/usr/bin/env bash

set -euo pipefail

main() {
  local command_name="${1:-}"

  case "$command_name" in
    # Editors
    vim|nvim|vi|hx) printf '\ue7c5\n' ;;
    nano) printf '\uf0f6\n' ;;
    emacs) printf '\ue7c2\n' ;;
    code|code-insiders|zed|subl) printf '\ue70c\n' ;;

    # AI coding agents
    claude|codex|opencode|mimo|aider|gemini|copilot|agy) printf '\U000f06a9\n' ;;

    # Shells and terminals
    bash|zsh|fish|sh|dash|nu) printf '\uf489\n' ;;

    # SSH
    ssh|scp|sftp|mosh) printf '\U000f08a9\n' ;;
    wezterm|ghostty|kitty|alacritty) printf '\uf120\n' ;;

    # Version control
    git|lazygit|tig|gitui) printf '\uf1d3\n' ;;
    gh) printf '\uf09b\n' ;;

    # Node/JavaScript
    node|yarn|pnpm|vite|next) printf '\ue718\n' ;;
    npm|npx) printf '\ue71e\n' ;;
    bun|redis-cli) printf '\ue76d\n' ;;
    deno) printf '\ue628\n' ;;

    # Python
    python|python3|pip|pipenv|poetry|uv|pytest|ipython) printf '\ue73c\n' ;;

    # Ruby
    ruby|irb|rails|bundle) printf '\ue739\n' ;;

    # Go and Rust
    go) printf '\ue627\n' ;;
    cargo|rustc) printf '\ue7a8\n' ;;

    # Java/JVM
    java|gradle|mvn) printf '\ue738\n' ;;

    # Containers and cloud tools
    docker|podman) printf '\uf308\n' ;;
    kubectl|k9s|kubecolor|helm) printf '\U000f10fe\n' ;;
    terraform) printf '\uf1bb\n' ;;

    # Databases
    psql) printf '\ue76e\n' ;;
    mysql) printf '\ue704\n' ;;
    mongosh) printf '\ue7a4\n' ;;

    # System tools
    htop|top|btop|btm|glances) printf '\U000f04c5\n' ;;
    tmux) printf '\uebc8\n' ;;

    # File managers and search tools
    ranger|nnn|yazi|lf|mc) printf '\uf07b\n' ;;
    fzf|rg|fd) printf '\uf002\n' ;;
    bat|man|less) printf '\uf02d\n' ;;

    # Network and build tools
    curl) printf '\uf0ac\n' ;;
    wget) printf '\uf0ed\n' ;;
    make|cmake) printf '\uf425\n' ;;

    # PowerKit's default icon for unmatched commands.
    *) printf '\uf120\n' ;;
  esac
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
