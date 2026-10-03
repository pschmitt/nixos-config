{
  basePkgs,
  inputs,
}:
let
  inherit (pkgs) lib;
  system = basePkgs.stdenv.hostPlatform.system;
  pkgs = import inputs.nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  };
  android = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    ndkVersions = [ "27.2.12479018" ];
    platformVersions = [ ];
    buildToolsVersions = [ ];
    includeEmulator = false;
  };
  ndkRoot = "${android.ndk-bundle}/libexec/android-sdk/ndk-bundle";
  toolchain = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/bin";
  profile = import ../../android/termux-native/profile.nix { inherit pkgs inputs; };
  homeManagerProfile = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [ ../../modules/home-manager/termux.nix ];
  };
  termuxNativePackages = builtins.filter (
    package: builtins.isAttrs ((package.passthru or { }).termuxNative or null)
  ) homeManagerProfile.config.home.packages;
  # Home Manager adds these to home.packages for activation and generated docs.
  # They are already handled explicitly by the bundle exporter where needed.
  homeManagerSupportPackages = [
    "dummy-xdg-mime-dirs1"
    "dummy-xdg-mime-dirs2"
    "hm-session-vars.sh"
    "home-configuration-reference-manpage"
    "man-db"
    "shared-mime-info"
  ];
  unsupportedHomePackages = builtins.filter (
    package:
    !(builtins.isAttrs ((package.passthru or { }).termuxNative or null))
    && !(builtins.elem (lib.getName package) homeManagerSupportPackages)
  ) homeManagerProfile.config.home.packages;
  termuxNativePackageManifest =
    if unsupportedHomePackages != [ ] then
      throw ''
        Termux Home Manager profile has packages with no Termux installation target: ${
          lib.concatMapStringsSep ", " (package: package.name) unsupportedHomePackages
        }.
        Add packages available from Termux to `termux.packages`, or mark an
        Android/Bionic derivation with `passthru.termuxNative` and its exported files.
      ''
    else
      pkgs.writeText "termux-native-home-packages.json" (
        builtins.toJSON (
          map (package: {
            inherit (package) name;
            path = toString package;
            inherit (package.passthru.termuxNative)
              files
              binaries
              ;
          }) termuxNativePackages
        )
      );
  manifest = (pkgs.formats.json { }).generate "termux-native-manifest.json" {
    schema = 1;
    architecture = "aarch64";
    minimumApi = 24;
    prefix = "/data/data/com.termux/files/usr";
    basePackages = homeManagerProfile.config.termux.packages;
    homePackages = map (package: package.name) termuxNativePackages;
    homeFiles = homeManagerProfile.config.termux.homeFiles;
    plugins = builtins.attrNames profile.plugins;
    gitstatusVersion = pkgs.gitstatus.version;
  };
  termuxPackages = homeManagerProfile.config.termux.packages;
  gitstatus = pkgs.runCommand "gitstatus-android-${pkgs.gitstatus.version}" {
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.gnumake
    ];
    inherit ndkRoot;
    gitstatusSource = pkgs.gitstatus.src;
    libgit2Source = pkgs.gitstatus.romkatv_libgit2.src;
    allowedReferences = [ ];
  } "bash ${../../android/termux-native/build-gitstatus.sh}";
  environment =
    pkgs.runCommand "termux-native-environment"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.jq
        ];
        allowedReferences = [ ];
      }
      ''
        mkdir -p "$out/bin" "$out/etc/profile.d" "$out/home" "$out/libexec" "$out/shell/plugins"
        ${toolchain}/aarch64-linux-android24-clang \
          -O2 -Wall -Wextra -Werror -fPIE -pie -Wl,-z,max-page-size=16384 \
          -Wl,-z,common-page-size=16384 \
          ${../../android/termux-native/hello.c} -o "$out/bin/termux-nix-hello"
        ${toolchain}/llvm-strip "$out/bin/termux-nix-hello"
        ${toolchain}/llvm-readelf -h -l -d "$out/bin/termux-nix-hello"
        ${toolchain}/aarch64-linux-android24-clang \
          -O2 -Wall -Wextra -Werror -fPIE -pie -Wl,-z,max-page-size=16384 \
          -Wl,-z,common-page-size=16384 \
          ${../../android/termux-native/launcher.c} \
          -o "$out/libexec/termux-native-launcher"
        ${toolchain}/llvm-strip "$out/libexec/termux-native-launcher"
        ${toolchain}/llvm-readelf -h -l -d "$out/libexec/termux-native-launcher"
        cp ${../../android/termux-native/plugin.zsh} "$out/shell/plugins/example.zsh"
        cp ${../../android/termux-native/activate.sh} "$out/activate.sh"
        cp ${../../android/termux-native/bootstrap.sh} "$out/bootstrap.sh"
        cp ${../../android/termux-native/zshenv} "$out/zshenv"
        substituteInPlace "$out/bootstrap.sh" \
          --replace-fail '@termuxPackages@' '${lib.escapeShellArgs termuxPackages}'
        cp ${../../android/termux-native/smoke-test.zsh} "$out/shell/smoke-test.zsh"
        cp ${../../android/termux-native/check-pty.zsh} "$out/shell/check-pty.zsh"
        cp ${../../android/termux-native/prompt.zsh} "$out/shell/prompt.zsh"
        cp ${../../android/termux-native/keybindings.zsh} "$out/shell/keybindings.zsh"
        cp ${gitstatus}/bin/gitstatusd "$out/bin/gitstatusd"
        cp ${manifest} "$out/manifest.json"
        bash ${../../android/termux-native/export-home-packages.sh} \
          ${termuxNativePackageManifest} \
          "$out" \
          ${toolchain}/llvm-readelf \
          ${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/24
        printf '%s\n' ${lib.escapeShellArgs homeManagerProfile.config.termux.packages} > "$out/base-packages.txt"
        for file in ${pkgs.lib.escapeShellArgs homeManagerProfile.config.termux.homeFiles}; do
          mkdir -p "$out/home/$(dirname "$file")"
          cp -RL "${homeManagerProfile.config."home-files"}/$file" "$out/home/$file"
        done
        sed '/^export LOCALE_ARCHIVE_2_27=/d' \
          ${homeManagerProfile.config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh \
          > "$out/etc/profile.d/hm-session-vars.sh"
        substituteInPlace "$out/home/.config/zsh/.zprofile" \
          --replace-fail \
          '${homeManagerProfile.config.home.sessionVariablesPackage}' \
          '$TERMUX_GENERATION'
        ${pkgs.lib.concatStringsSep "\n" (
          pkgs.lib.mapAttrsToList (name: source: ''
            cp -R ${source} "$out/shell/plugins/${name}"
          '') profile.plugins
        )}
        mkdir -p "$out/share/licenses"
        cp ${pkgs.gitstatus.src}/LICENSE "$out/share/licenses/gitstatus"
        cp ${pkgs.gitstatus.romkatv_libgit2.src}/COPYING "$out/share/licenses/libgit2"
      '';
  bundle = pkgs.runCommand "termux-native-bundle" { allowedReferences = [ ]; } ''
    mkdir -p "$out"
    tar --hard-dereference --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
      -C ${environment} -cf - . | gzip -n > "$out/environment.tar.gz"
    cd "$out"
    sha256sum environment.tar.gz > SHA256SUMS
    cp ${environment}/activate.sh ${environment}/bootstrap.sh "$out/"
    cp ${manifest} "$out/manifest.json"
  '';
in
{
  inherit bundle environment gitstatus;
}
