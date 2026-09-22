#!/usr/bin/env bash
set -euxo pipefail

build_host=""
host="pica4"
remaining=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --build-host)
      build_host="${args[$((i + 1))]}"
      ((i += 1))
      ;;
    -*)
      remaining+=("${args[$i]}")
      ;;
    *)
      host="${args[$i]}"
      ;;
  esac
done
if [[ -n "$build_host" ]]; then
  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh --host "$build_host" nixos)"
  trap "ssh '$build_host' rm -rf '$BUILD_DIR'" EXIT
  ssh "$build_host" \
    nix build --print-build-logs \
    "${BUILD_DIR}#nixosConfigurations.${host}.config.system.build.sdImage" \
    "${remaining[@]+"${remaining[@]}"}"
else
  ./scripts/build-installation-media.sh sd-image "$host" "${remaining[@]+"${remaining[@]}"}"
fi
