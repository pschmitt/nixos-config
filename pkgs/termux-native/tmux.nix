{
  dpkg,
  fetchurl,
  lib,
  runCommand,
}:
let
  package =
    {
      name,
      version,
      hash,
    }:
    fetchurl {
      url = "https://packages.termux.dev/apt/termux-main/pool/main/${
        builtins.substring 0 (if lib.hasPrefix "lib" name then 4 else 1) name
      }/${name}/${name}_${version}_aarch64.deb";
      inherit hash;
    };

  tmux = package {
    name = "tmux";
    version = "3.7c-1";
    hash = "sha256-9zShpOezV2GZttzmm/fTxD0X3ZZviiNOtaop7QNV7CY=";
  };
  ncurses = package {
    name = "ncurses";
    version = "6.6.20260307+really6.5.20250830";
    hash = "sha256-9Eu/3D1C7AIXv/qXgwk5DlnOpaSKmoMibUpJbEKtC5k=";
  };
  libevent = package {
    name = "libevent";
    version = "2.1.13";
    hash = "sha256-z5no5s0SGMDklW0u5p77smUgIRs+A0B0Y+rJAW/lXyU=";
  };
  libandroidSupport = package {
    name = "libandroid-support";
    version = "29-1";
    hash = "sha256-8vFF1hNa1IQ6yWcBU74+OUTcHm8XNtRtIwbCjyuG9Rc=";
  };
  libandroidGlob = package {
    name = "libandroid-glob";
    version = "0.6-3";
    hash = "sha256-Inauit7fDbdsL0/8lMxMzrL09deOAhtU4uBG0SM+eCY=";
  };
  utf8proc = package {
    name = "utf8proc";
    version = "2.12.0";
    hash = "sha256-K1iGsEAw6VfhtlIvqhCoFwqyA9QLYLBs+Mf5of8sJNE=";
  };
in
runCommand "tmux-termux-3.7c"
  {
    nativeBuildInputs = [ dpkg ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      files = [
        "bin/tmux"
        "lib/libandroid-glob.so"
        "lib/libandroid-support.so"
        "lib/libevent_core-2.1.so"
        "lib/libncursesw.so.6"
        "lib/libutf8proc.so.3"
        "share/licenses/libandroid-glob"
        "share/licenses/libevent"
        "share/licenses/ncurses"
        "share/licenses/tmux"
        "share/licenses/utf8proc"
      ];
      binaries = [ "bin/tmux" ];
    };
    meta = {
      description = "Terminal multiplexer from the official Termux package repository";
      homepage = "https://github.com/tmux/tmux";
      license = [
        lib.licenses.asl20
        lib.licenses.isc
        lib.licenses.bsd3
        lib.licenses.mit
      ];
      mainProgram = "tmux";
    };
  }
  ''
    extract() {
      local package=$1 destination=$2
      mkdir -p "$destination"
      dpkg-deb -x "$package" "$destination"
    }

    extract ${tmux} "$TMPDIR/tmux"
    extract ${ncurses} "$TMPDIR/ncurses"
    extract ${libevent} "$TMPDIR/libevent"
    extract ${libandroidSupport} "$TMPDIR/libandroid-support"
    extract ${libandroidGlob} "$TMPDIR/libandroid-glob"
    extract ${utf8proc} "$TMPDIR/utf8proc"

    prefix="$TMPDIR/tmux/data/data/com.termux/files/usr"
    install -Dm0755 "$prefix/bin/tmux" "$out/bin/tmux"
    install -Dm0755 \
      "$TMPDIR/libandroid-support/data/data/com.termux/files/usr/lib/libandroid-support.so" \
      "$out/lib/libandroid-support.so"
    install -Dm0755 \
      "$TMPDIR/libandroid-glob/data/data/com.termux/files/usr/lib/libandroid-glob.so" \
      "$out/lib/libandroid-glob.so"
    install -Dm0755 \
      "$TMPDIR/libevent/data/data/com.termux/files/usr/lib/libevent_core-2.1.so" \
      "$out/lib/libevent_core-2.1.so"
    install -Dm0755 \
      "$TMPDIR/ncurses/data/data/com.termux/files/usr/lib/libncursesw.so.6" \
      "$out/lib/libncursesw.so.6"
    install -Dm0755 \
      "$TMPDIR/utf8proc/data/data/com.termux/files/usr/lib/libutf8proc.so.3" \
      "$out/lib/libutf8proc.so.3"

    for package in tmux libevent ncurses libandroid-glob utf8proc; do
      source="$TMPDIR/$package/data/data/com.termux/files/usr/share/doc/$package/copyright"
      if [[ -f "$source" ]]; then
        install -Dm0644 "$source" "$out/share/licenses/$package"
      fi
    done
  ''
