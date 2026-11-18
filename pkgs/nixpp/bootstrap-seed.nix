# The full-Nix runtime's launcher and bootstrap seed, built from the pinned
# droid-nix sources (MIT, see inputs.droid-nix-src) instead of taking them from
# a prebuilt droid-nix APK.
#
# - share/nixpp/launcher: the static seccomp launcher (bootstrap/launcher).
# - share/nixpp/manifest.json: the pinned session packages (session-manifest.nix).
# - share/nixpp/bootstrap-aarch64.zip: a registered chroot store holding
#   static nix and busybox plus the Linux nixpp closure, plus EXECUTABLES.txt and SYMLINKS.txt
#   (ZIP entries cannot carry modes or links; nixpp restores both).
#
# Everything else comes from cache.nixos.org during `nixpp init`. nixpp writes
# /etc, /bin/sh and the guest user itself, so droid-nix's login scripts and
# etc module are not part of the seed.
{
  lib,
  pkgs,
  inputs,
}:
let
  src = inputs.droid-nix-src;

  # Static aarch64 binaries, cross-compiled against musl; cache.nixos.org has
  # no static aarch64 nix.
  static = pkgs.pkgsCross.aarch64-multiplatform-musl.pkgsStatic;

  # The nix command alone: nix-everything also pulls in nix-nswrapper, which
  # the runtime cannot use (no user namespaces, sandbox = false).
  nix =
    (static.nixVersions.nixComponents_2_34.overrideScope (
      _: prev: {
        nix-util = prev.nix-util.overrideAttrs (old: {
          patches = old.patches or [ ] ++ [ "${src}/bootstrap/nix-util-syscall-h.patch" ];
        });
        nix-cli = prev.nix-cli.overrideAttrs { stripAllList = [ "bin" ]; };
      }
    )).nix-cli;
  inherit (static) busybox;

  # Android's app seccomp filter traps openat2 (Android 15); the upstream
  # handler re-translated its own reissue until the stack overflowed.
  launcher = (static.callPackage "${src}/bootstrap/launcher" { }).overrideAttrs (old: {
    patches = old.patches or [ ] ++ [ ./launcher-foreign-trap.patch ];
  });

  guestNixpp = pkgs.pkgsCross.aarch64-multiplatform.callPackage ./. { };
  manifest = import ./session-manifest.nix { inherit pkgs inputs guestNixpp; };

  closure = pkgs.closureInfo {
    rootPaths = [
      nix
      busybox
      guestNixpp
    ];
  };
in
pkgs.runCommand "termuxpp-nix-bootstrap-seed"
  {
    nativeBuildInputs = [
      pkgs.nix
      pkgs.sqlite
      pkgs.zip
    ];
    passthru = {
      inherit
        launcher
        nix
        busybox
        manifest
        ;
      termuxNative.files = [
        "share/nixpp/launcher"
        "share/nixpp/bootstrap-aarch64.zip"
        "share/nixpp/manifest.json"
      ];
    };
    meta = {
      description = "Launcher and bootstrap seed for the TermuxPP full-Nix runtime";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    root=$PWD/seed
    mkdir -p "$root/nix/store"
    for path in $(< ${closure}/store-paths); do
      cp --archive "$path" "$root$path"
    done
    export HOME=$TMPDIR
    nix-store --store "$root" --load-db < ${closure}/registration
    rm -f "$root/nix/var/nix/db/reserved"
    # Fold the write-ahead log into db.sqlite so the seed holds one consistent
    # database file instead of transient -wal/-shm companions.
    # Registration times are the build time; pin them for a reproducible seed.
    sqlite3 "$root/nix/var/nix/db/db.sqlite" \
      'UPDATE ValidPaths SET registrationTime = 1; PRAGMA journal_mode=DELETE;' > /dev/null
    rm -f "$root"/nix/var/nix/db/db.sqlite-{wal,shm}
    chmod -R u+w "$root/nix"
    mkdir -p "$root"/nix/var/nix/{profiles,gcroots}

    cd "$root"
    # Paths relative to the runtime root, as nixpp's extraction expects.
    find nix -type f -perm -u+x | LC_ALL=C sort > EXECUTABLES.txt
    find nix -type l | LC_ALL=C sort | while read -r link; do
      printf '%s←%s\n' "$(readlink "$link")" "$link"
      rm "$link"
    done > SYMLINKS.txt

    # Reproducible archive: fixed timestamps, sorted members, no extra fields.
    find . -exec touch -h -d @1 {} +
    mkdir -p "$out/share/nixpp"
    find . -mindepth 1 | LC_ALL=C sort | zip -q -X -9 -@ "$out/share/nixpp/bootstrap-aarch64.zip"
    install -m 0755 ${launcher}/bin/launcher "$out/share/nixpp/launcher"
    install -m 0644 ${manifest} "$out/share/nixpp/manifest.json"
  ''
