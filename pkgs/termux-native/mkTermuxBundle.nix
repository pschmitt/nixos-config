{
  basePkgs,
  inputs,
  modules ? [ ],
  extraSpecialArgs ? { },
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
    overlays = builtins.attrValues (import ../../overlays { inherit inputs; });
  };
  target = import ./target.nix { inherit pkgs; };
  inherit (target) apiLevel ndkRoot;
  profile = import ../../android/termux-native/profile.nix { inherit pkgs inputs; };
  elfCleaner = pkgs.callPackage ./elf-cleaner.nix { };
  homeManagerProfile = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      hostname = "termux";
    }
    // extraSpecialArgs;
    modules = [ ../../modules/home-manager/termux.nix ] ++ modules;
  };
  homeFileSources = map (
    path:
    let
      absolutePath = "${homeManagerProfile.config.home.homeDirectory}/${lib.removePrefix "/" path}";
      sourcePath =
        if builtins.hasAttr path homeManagerProfile.config.home.file then
          path
        else if builtins.hasAttr absolutePath homeManagerProfile.config.home.file then
          absolutePath
        else
          throw "Termux home file is not configured: ${path}";
    in
    {
      inherit path;
      source = builtins.path {
        path = toString homeManagerProfile.config.home.file.${sourcePath}.source;
        name = builtins.baseNameOf path;
      };
    }
  ) homeManagerProfile.config.termux.homeFiles;
  homeFiles = pkgs.runCommand "termux-native-home-files" { } ''
    mkdir -p "$out/home"
    ${lib.concatMapStringsSep "\n" (file: ''
      mkdir -p "$out/home/$(dirname ${lib.escapeShellArg file.path})"
      cp -RL ${lib.escapeShellArg (toString file.source)} "$out/home/${file.path}"
    '') homeFileSources}
  '';
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
              abi
              files
              binaries
              ;
            scripts = package.passthru.termuxNative.scripts or [ ];
            trees = package.passthru.termuxNative.trees or [ ];
            aptPackages = package.passthru.termuxNative.aptPackages or [ ];
            runtimeClosure = package.passthru.termuxNative.runtimeClosure or null;
          }) termuxNativePackages
        )
      );
  manifest = (pkgs.formats.json { }).generate "termux-native-manifest.json" {
    schema = 1;
    inherit (target) architecture prefix;
    minimumApi = apiLevel;
    basePackages = termuxPackages;
    homePackages = map (package: package.name) termuxNativePackages;
    homeFiles = homeManagerProfile.config.termux.homeFiles;
    plugins = builtins.attrNames profile.plugins;
    gitstatusVersion = pkgs.gitstatus.version;
  };
  termuxPackages = lib.unique (
    homeManagerProfile.config.termux.packages
    ++ lib.concatMap (package: package.passthru.termuxNative.aptPackages or [ ]) termuxNativePackages
  );
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
          pkgs.patchelf
          elfCleaner
        ];
        allowedReferences = [ ];
      }
      ''
        mkdir -p "$out/bin" "$out/etc/profile.d" "$out/home" "$out/libexec" "$out/shell/plugins"
        ${target.cc} \
          -O2 -Wall -Wextra -Werror -fPIE -pie -Wl,-z,max-page-size=16384 \
          -Wl,-z,common-page-size=16384 \
          ${../../android/termux-native/hello.c} -o "$out/bin/termux-nix-hello"
        ${target.strip} "$out/bin/termux-nix-hello"
        ${target.readelf} -h -l -d "$out/bin/termux-nix-hello"
        ${target.cc} \
          -O2 -Wall -Wextra -Werror -fPIE -pie -Wl,-z,max-page-size=16384 \
          -Wl,-z,common-page-size=16384 \
          ${../../android/termux-native/launcher.c} \
          -o "$out/libexec/termux-native-launcher"
        ${target.strip} "$out/libexec/termux-native-launcher"
        ${target.readelf} -h -l -d "$out/libexec/termux-native-launcher"
        cp ${../../android/termux-native/plugin.zsh} "$out/shell/plugins/example.zsh"
        cp ${../../android/termux-native/activate.sh} "$out/activate.sh"
        cp ${../../android/termux-native/bootstrap.sh} "$out/bootstrap.sh"
        cp ${../../android/termux-native/zshenv} "$out/zshenv"
        cp ${../../android/termux-native/smoke-test.zsh} "$out/shell/smoke-test.zsh"
        cp ${../../android/termux-native/check-pty.zsh} "$out/shell/check-pty.zsh"
        cp ${../../android/termux-native/prompt.zsh} "$out/shell/prompt.zsh"
        cp ${gitstatus}/bin/gitstatusd "$out/bin/gitstatusd"
        chmod u+w "$out/bin/gitstatusd"
        ${elfCleaner}/bin/termux-elf-cleaner --api-level ${toString apiLevel} \
          "$out/bin/termux-nix-hello" \
          "$out/libexec/termux-native-launcher" \
          "$out/bin/gitstatusd"
        chmod u-w "$out/bin/gitstatusd"
        cp ${manifest} "$out/manifest.json"
        printf '%s\n' ${lib.escapeShellArgs termuxPackages} > "$out/base-packages.txt"
        cp -RL ${homeFiles}/home/. "$out/home/"
        sed '/^export LOCALE_ARCHIVE_2_27=/d' \
          ${homeManagerProfile.config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh \
          > "$out/etc/profile.d/hm-session-vars.sh"
        substituteInPlace "$out/home/.config/zsh/.zprofile" \
          --replace-fail \
          '${homeManagerProfile.config.home.sessionVariablesPackage}' \
          '$TERMUX_GENERATION'
        substituteInPlace "$out/home/.config/zsh/.zshenv" \
          --replace-fail \
          '${homeManagerProfile.config.home.sessionVariablesPackage}' \
          '$TERMUX_GENERATION'
        substituteInPlace "$out/home/.config/zsh/.zshenv" \
          --replace-fail \
          'export ZDOTDIR="${homeManagerProfile.config.xdg.configHome}/zsh"' \
          'export ZDOTDIR="$TERMUX_GENERATION/home/.config/zsh"'
        ${pkgs.lib.concatStringsSep "\n" (
          pkgs.lib.mapAttrsToList (name: source: ''
            cp -R ${source} "$out/shell/plugins/${name}"
          '') profile.plugins
        )}
        mkdir -p "$out/share/licenses"
        cp ${pkgs.gitstatus.src}/LICENSE "$out/share/licenses/gitstatus"
        cp ${pkgs.gitstatus.romkatv_libgit2.src}/COPYING "$out/share/licenses/libgit2"
        bash ${../../android/termux-native/export-home-packages.sh} \
          ${termuxNativePackageManifest} \
          "$out" \
          ${target.readelf} \
          ${target.sysrootLib} \
          ${pkgs.patchelf}/bin/patchelf \
          ${elfCleaner}/bin/termux-elf-cleaner \
          ${toString apiLevel}
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
