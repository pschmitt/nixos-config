{ lib
, rustPlatform
, fetchFromGitHub
, installShellFiles
, pkg-config
, cairo
, libGL
, libgit2
, libxkbcommon
, ncurses
, openssl
, perl
, sqlite
, vulkan-loader
, zlib
, zstd
, stdenv
, darwin
, wayland
, xorg
, xcbutil
, xcbutilimage
, xcbutilkeysyms
, xcbutilwm
, nixosTests
, runCommand
}:

rustPlatform.buildRustPackage rec {
  pname = "wezterm";
  # Date of the commit and commit sha
  # gh api repos/wez/wezterm/commits --jq '.[0] | "\(.commit.committer.date | strptime("%Y-%m-%dT%H:%M:%S%z") | strftime("%Y%m%d"))-\(.sha[0:6])"'
  version = "20231222-84ae00c";

  # FIXME The tests fail with:
  # wezterm> test result: FAILED. 0 passed; 37 failed; 0 ignored; 0 measured;  0 filtered out; finished in 0.01s
  # wezterm> error: test failed, to rerun pass `-p wezterm-ssh --test lib`
  doCheck = false;

  src = fetchFromGitHub {
    owner = "wez";
    repo = "wezterm";
    # git ls-remote --heads https://github.com/wez/wezterm main | awk '{ print $1 }'
    rev = "84ae00c868e711cf97b2bfe885892428f1131a1d";
    hash = "sha256-Sx5NtapMe+CtSlW9mfxUHhzF+n9tV2j/St6pku26Rj0=";
    fetchSubmodules = true;
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "xcb-1.2.1" = "sha256-zkuW5ATix3WXBAj2hzum1MJ5JTX3+uVQ01R1vL6F1rY=";
      "xcb-imdkit-0.2.0" = "sha256-L+NKD0rsCk9bFABQF4FZi9YoqBHr4VAZeKAWgsaAegw=";
    };
  };

  nativeBuildInputs = [
    installShellFiles
    pkg-config
  ] ++ lib.optional stdenv.isDarwin perl;

  buildInputs = [
    cairo
    libgit2
    libxkbcommon
    xcbutil
    xcbutilimage
    xcbutilkeysyms
    xcbutilwm # contains xcb-ewmh among others
    openssl
    sqlite
    vulkan-loader
    zlib
    zstd
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.AppKit
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.CoreGraphics
    darwin.apple_sdk.frameworks.CoreServices
    darwin.apple_sdk.frameworks.CoreText
    darwin.apple_sdk.frameworks.Foundation
    darwin.apple_sdk.frameworks.Metal
    darwin.apple_sdk.frameworks.QuartzCore
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.SystemConfiguration
  ] ++ lib.optionals stdenv.isLinux [
    wayland
    xorg.libX11
    xorg.libxcb
  ];

  env = {
    OPENSSL_NO_VENDOR = true;
    ZSTD_SYS_USE_PKG_CONFIG = true;
  };

  postPatch = ''
    echo ${version} > .tag

    # tests are failing with: Unable to exchange encryption keys
    rm -r wezterm-ssh/tests
  '';


  postInstall = ''
    mkdir -p $out/nix-support
    echo "${passthru.terminfo}" >> $out/nix-support/propagated-user-env-packages

    install -Dm644 assets/icon/terminal.png $out/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
    install -Dm644 assets/wezterm.desktop $out/share/applications/org.wezfurlong.wezterm.desktop
    install -Dm644 assets/wezterm.appdata.xml $out/share/metainfo/org.wezfurlong.wezterm.appdata.xml

    install -Dm644 assets/shell-integration/wezterm.sh -t $out/etc/profile.d

    installShellCompletion --cmd wezterm \
      --bash assets/shell-completion/bash \
      --fish assets/shell-completion/fish \
      --zsh assets/shell-completion/zsh

    install -Dm644 assets/wezterm-nautilus.py -t $out/share/nautilus-python/extensions
  '';

  preFixup = lib.optionalString stdenv.isLinux ''
    patchelf \
      --add-needed "${libGL}/lib/libEGL.so.1" \
      --add-needed "${vulkan-loader}/lib/libvulkan.so.1" \
      $out/bin/wezterm-gui
  '' + lib.optionalString stdenv.isDarwin ''
    mkdir -p "$out/Applications"
    OUT_APP="$out/Applications/WezTerm.app"
    cp -r assets/macos/WezTerm.app "$OUT_APP"
    rm $OUT_APP/*.dylib
    cp -r assets/shell-integration/* "$OUT_APP"
    ln -s $out/bin/{wezterm,wezterm-mux-server,wezterm-gui,strip-ansi-escapes} "$OUT_APP"
  '';

  passthru = {
    tests = {
      all-terminfo = nixosTests.allTerminfo;
      terminal-emulators = nixosTests.terminal-emulators.wezterm;
    };
    terminfo = runCommand "wezterm-terminfo"
      {
        nativeBuildInputs = [ ncurses ];
      } ''
      mkdir -p $out/share/terminfo $out/nix-support
      tic -x -o $out/share/terminfo ${src}/termwiz/data/wezterm.terminfo
    '';
  };

  meta = with lib; {
    description = "A GPU-accelerated cross-platform terminal emulator and multiplexer written by @wez and implemented in Rust";
    homepage = "https://github.com/wez/wezterm";
    license = licenses.mit;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "wezterm";
  };
}
