#!/usr/bin/env bash

main() {
  set -euo pipefail
  : "${ndkRoot:?}" "${libgit2Source:?}" "${gitstatusSource:?}" "${out:?}"
  local compiler="$ndkRoot/toolchains/llvm/prebuilt/linux-x86_64/bin"
  cp -R "$libgit2Source" libgit2
  chmod -R u+w libgit2
  cmake -S libgit2 -B libgit2/build \
    -DCMAKE_TOOLCHAIN_FILE="$ndkRoot/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_CLAR=OFF -DBUILD_SHARED_LIBS=OFF -DREGEX_BACKEND=builtin \
    -DUSE_GSSAPI=OFF -DUSE_HTTPS=OFF -DUSE_HTTP_PARSER=builtin \
    -DUSE_NTLMCLIENT=OFF -DUSE_SSH=OFF -DZERO_NSEC=ON
  cmake --build libgit2/build --parallel "${NIX_BUILD_CORES:-2}"
  cp -R "$gitstatusSource" gitstatus
  chmod -R u+w gitstatus
  make -C gitstatus -j "${NIX_BUILD_CORES:-2}" \
    CXX="$compiler/aarch64-linux-android24-clang++" \
    CXXFLAGS="-std=c++14 -O2 -fPIE -funsigned-char -DNDEBUG -DGITSTATUS_VERSION=v1.5.5 -DGITSTATUS_ZERO_NSEC -I$PWD/libgit2/include" \
    LDFLAGS="-pie -static-libstdc++ -L$PWD/libgit2/build -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" \
    LDLIBS="-lgit2 -lz -ldl"
  install -Dm755 gitstatus/usrbin/gitstatusd "$out/bin/gitstatusd"
  "$compiler/llvm-strip" "$out/bin/gitstatusd"
  "$compiler/llvm-readelf" -l -d "$out/bin/gitstatusd"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
