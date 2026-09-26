#!/usr/bin/env bash

set -Eeuo pipefail

readonly package_list=(
  build-essential
  cmake
  curl
  fzf
  gh
  git
  golang
  jq
  libxml2
  libxslt
  nodejs
  openssl-tool
  pinentry
  python
  python-cryptography
  python-lxml
  python-pip
  python-psutil
  python-rpds-py
  rust
  tmux
  unzip
  uv
  zsh
)

main() {
  local dpkg_arch cache_arch python_version rc log_file tmux_log_file plugin_errors zinit_timeout
  local -i start_time=$SECONDS
  local -a archive_paths=(share)
  local -a configured_packages=()

  if [[ "$#" -ne 4 ]]
  then
    printf 'Cache input metadata is incomplete\n' >&2
    return 2
  fi
  export YADM_ZSH_TREE="$1"
  export YADM_TMUX_TREE="$2"
  export YADM_TERMUX_PACKAGES_BLOB="$3"
  zinit_timeout=$4
  if [[ ! "$zinit_timeout" =~ ^[[:digit:]]+[smhd]?$ ]]
  then
    printf 'Invalid zinit scheduler timeout\n' >&2
    return 2
  fi

  dpkg_arch=$(dpkg --print-architecture)
  case "$dpkg_arch" in
    aarch64|arm64)
      cache_arch=aarch64
      ;;
    amd64|x86_64)
      cache_arch=x86_64
      ;;
    *)
      printf 'Unsupported Termux architecture: %s\n' "$dpkg_arch" >&2
      return 1
      ;;
  esac

  if [[ "$cache_arch" != aarch64 && "${TERMUX_CACHE_ALLOW_NON_AARCH64:-}" != 1 ]]
  then
    printf 'Expected an AArch64 Termux environment\n' >&2
    return 1
  fi

  export TMPDIR="$PREFIX/tmp/zinit-cache-build"
  mkdir -p "$TMPDIR" /output

  apt_step() {
    local log_name="$1" rc
    shift

    if "$@" >"$TMPDIR/$log_name" 2>&1
    then
      return 0
    else
      rc=$?
      cp "$TMPDIR/$log_name" "/output/$log_name"
      printf 'Termux package command failed with status %s; log retained on the builder: %s\n' "$rc" "$log_name" >&2
      tail -n 80 "$TMPDIR/$log_name" >&2
      return "$rc"
    fi
  }

  apt_step apt-update-1.log apt update
  apt_step apt-upgrade.log apt full-upgrade -y
  apt_step apt-repos.log apt install -y root-repo unstable-repo yq
  apt_step apt-update-2.log apt update
  mapfile -t configured_packages < <(yq -r '.packages[]' /input/.config/yadm/ansible-bootstrap/roles/cli/vars/packages_termux.yml)
  if [[ "${#configured_packages[@]}" -eq 0 ]]; then
    printf 'Termux package list was empty\n' >&2
    return 1
  fi
  apt_step apt-packages.log apt install -y "${package_list[@]}" "${configured_packages[@]}"
  if ! command -v uv >/dev/null 2>&1 || ! uv --version
  then
    printf 'Termux uv package is unavailable; refusing to build an incomplete Zinit cache\n' >&2
    return 1
  fi

  # This marks the container as Termux for OS-specific config and secret guards.
  # It must not suppress Zinit plugin installation or the zinit::uv helper.
  export TERMUX_RUN_MODE=ci
  # Maturin cannot infer Android's API level inside the QEMU Termux container.
  # Match the API level used by Termux's aarch64-linux-android-clang wrapper.
  export ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-24}"
  export TERM=xterm
  export ZINIT_SCHEDULER_BURST=1
  export ZDOTDIR=/input/.config/zsh
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_BIN_HOME="$HOME/.local/bin"
  export TMUX_PLUGIN_MANAGER_PATH="$XDG_DATA_HOME/tpm"
  unset LD_PRELOAD

  mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_BIN_HOME" "$TMPDIR" /output "$XDG_CONFIG_HOME"
  ln -sfn /input/.config/tmux "$XDG_CONFIG_HOME/tmux"
  python_version=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')

  log_file="$TMPDIR/zinit-install.log"
  # The Termux zsh process expands these variables after bash starts it.
  # shellcheck disable=SC2016
  if timeout --kill-after=30s "$zinit_timeout" zsh -lc 'hash -d zsh="$ZDOTDIR"; source "$ZDOTDIR/zshrc" && @zinit-scheduler burst' >"$log_file" 2>&1
  then
    :
  else
    rc=$?
    cp "$log_file" /output/zinit-install.log
    printf 'zinit scheduler failed with status %s; private build log retained on the builder\n' "$rc" >&2
    return "$rc"
  fi

  if [[ ! -s "$log_file" ]]
  then
    printf 'zinit scheduler produced no log output; refusing to cache an unverified run\n' >&2
    return 1
  fi

  plugin_errors=$(
    grep -Ei 'error:|Warning: .*zinit-atclone-hook hook returned with|Error: linkbin: lbin ice .* did not match any files|Failed to build|cannot find GOROOT|unknown command|bad interpreter:|command not found:' "$log_file" |
      grep -Fvi "ERROR: pip's dependency resolver does not currently take into account" || true
  )
  if [[ -n "$plugin_errors" ]]
  then
    cp "$log_file" /output/zinit-install.log
    printf 'zinit scheduler reported plugin errors; private build log retained on the builder\n' >&2
    return 1
  fi

  if [[ ! -d "$XDG_DATA_HOME/zinit/plugins/linkding-cli" ]]
  then
    cp "$log_file" /output/zinit-install.log
    printf 'zinit scheduler did not cache the linkding-cli plugin; private build log retained on the builder\n' >&2
    return 1
  fi

  if [[ ! -x "$XDG_DATA_HOME/uv/tools/linkding-cli/bin/linkding" ]] ||
    [[ ! -x "$HOME/.local/bin/linkding" ]] ||
    ! uv tool list | grep -Eq '^linkding-cli v[[:digit:]]'
  then
    cp "$log_file" /output/zinit-install.log
    printf 'zinit::uv did not install the linkding tool and command shim; private build log retained on the builder\n' >&2
    return 1
  fi

  tmux_log_file="$TMPDIR/tmux-plugin-install.log"
  if timeout --kill-after=30s 2m tmux -f "$XDG_CONFIG_HOME/tmux/tmux.conf" new-session -d -s termux-cache-smoke >"$tmux_log_file" 2>&1
  then
    :
  else
    rc=$?
    cp "$tmux_log_file" /output/tmux-plugin-install.log
    printf 'tmux failed to load its configuration with status %s\n' "$rc" >&2
    tmux kill-server >/dev/null 2>&1 || true
    return "$rc"
  fi

  if timeout --kill-after=30s 30m "$XDG_CONFIG_HOME/tmux/tpm/bin/install_plugins" >>"$tmux_log_file" 2>&1
  then
    :
  else
    rc=$?
    cp "$tmux_log_file" /output/tmux-plugin-install.log
    printf 'tmux plugin installation failed with status %s\n' "$rc" >&2
    tmux kill-server >/dev/null 2>&1 || true
    return "$rc"
  fi

  if grep -Eiq 'download fail|fatal:|error:' "$tmux_log_file"
  then
    cp "$tmux_log_file" /output/tmux-plugin-install.log
    printf 'tmux plugin installer reported errors\n' >&2
    tmux kill-server >/dev/null 2>&1 || true
    return 1
  fi

  tmux kill-server >/dev/null 2>&1 || true
  [[ -d "$HOME/.local/bin" ]] && archive_paths+=(bin)
  [[ -d "$HOME/.local/lib" ]] && archive_paths+=(lib)

  tar --hard-dereference -czf /output/termux-home.tar.gz \
    --exclude='share/cargo/registry' \
    --exclude='share/cargo/git' \
    --exclude='share/go/pkg/mod' \
    --exclude='share/go/pkg/sumdb' \
    -C "$HOME/.local" "${archive_paths[@]}"
  (cd /output && sha256sum termux-home.tar.gz > termux-home.tar.gz.sha256)

  rm -rf -- "$TMPDIR"
  mkdir -p "$PREFIX/tmp"
  apt clean >/dev/null

  # OpenSSH installation creates host identity keys. Never publish the
  # builder's keys; the initializer generates a fresh key per device.
  rm -f -- "$PREFIX"/etc/ssh/ssh_host_*_key "$PREFIX"/etc/ssh/ssh_host_*_key.pub

  # Services stay disabled until the device-specific yadm setup enables them.
  for service in sshd ssh-agent
  do
    service_dir="$PREFIX/var/service/$service"
    if [[ ! -d "$service_dir" ]]
    then
      printf 'Termux service directory is missing: %s\n' "$service_dir" >&2
      return 1
    fi
    "$PREFIX/bin/sv" down "$service_dir" >/dev/null 2>&1 || true
    : > "$service_dir/down"
    if [[ ! -f "$service_dir/down" ]]
    then
      printf 'Could not disable Termux service: %s\n' "$service" >&2
      return 1
    fi
  done

  tar -czf /output/termux-prefix.tar.gz \
    --exclude='usr/var/run' \
    --exclude='usr/var/log/sv' \
    --exclude='usr/var/service/*/supervise' \
    --exclude='usr/var/service/*/log/supervise' \
    -C /data/data/com.termux/files usr
  (cd /output && sha256sum termux-prefix.tar.gz > termux-prefix.tar.gz.sha256)

  printf 'format=4\nzsh_tree=%s\ntmux_tree=%s\ntermux_packages=%s\narch=%s\npython=%s\npackage_count=%s\n' \
    "$YADM_ZSH_TREE" "$YADM_TMUX_TREE" "$YADM_TERMUX_PACKAGES_BLOB" "$cache_arch" "$python_version" \
    "$(dpkg-query -W -f='${binary:Package}\n' | wc -l)" \
    > /output/termux-environment.manifest
  printf 'zinit and tmux cache completed in %s seconds\n' "$((SECONDS - start_time))"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=bash et ts=2 sw=2 :
