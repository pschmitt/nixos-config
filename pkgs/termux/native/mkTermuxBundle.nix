{
  basePkgs,
  inputs,
  modules ? [ ],
  extraSpecialArgs ? { },
  termuxpp ? false,
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
    overlays = builtins.attrValues (import ../../../overlays { inherit inputs; });
  };
  target = import ./target.nix { inherit pkgs; };
  inherit (target) apiLevel ndkRoot;
  profile = import ../../../android/termux-native/profile.nix { inherit pkgs inputs; };
  elfCleaner = pkgs.callPackage ./elf-cleaner.nix { };
  homeManagerProfile = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      hostname = "termux";
    }
    // extraSpecialArgs;
    modules = [ ../../../modules/home-manager/termux.nix ] ++ modules;
  };
  nvimInitLua = homeManagerProfile.config.xdg.configFile."nvim/init.lua".text;
  nvimDevPathParts = lib.splitString "dev = {\n  path = \"" nvimInitLua;
  nvimDevPathFunction = lib.any (line: lib.hasInfix "path = function(plugin)" line) (
    lib.splitString "\n" nvimInitLua
  );
  nvimDevPathReturnParts = lib.splitString "return \"" nvimInitLua;
  nvimDevPathReturn = lib.findFirst (
    part: lib.hasInfix "plugin.name" part
  ) null nvimDevPathReturnParts;
  nvimDevPath =
    if lib.length nvimDevPathParts == 2 then
      lib.head (lib.splitString "\"" (lib.elemAt nvimDevPathParts 1))
    else if nvimDevPathFunction && nvimDevPathReturn != null then
      lib.removeSuffix "/" (lib.head (lib.splitString "\"" nvimDevPathReturn))
    else
      throw "Termux Neovim init.lua does not contain the expected LazyVim dev path.";
  nvimLazyDir = if nvimDevPathFunction then "folke--lazy.nvim" else "lazy.nvim";
  nvimLazyPath = "${nvimDevPath}/${nvimLazyDir}";
  nvimLazyAssignment = lib.head (
    lib.filter (line: lib.hasPrefix "local lazypath = " line) (lib.splitString "\n" nvimInitLua)
  );
  # Extra plugin sources, keyed by the "owner/repo" spelled in the Lazy specs.
  # LazyVim's dev path function resolves a plugin by its repository URL to
  # "<owner>--<repo>"; the plugin name (which a spec may override) is not used.
  termuxNvimPlugins = {
    "vimwiki/vimwiki" = pkgs.vimPlugins.vimwiki.src;
    "taybart/b64.nvim" = pkgs.vimPlugins.b64-nvim.src;
    "lucidph3nx/nvim-sops" = pkgs.vimPlugins.nvim-sops.src;
    "m00qek/baleia.nvim" = pkgs.vimPlugins.baleia-nvim.src;
    "norcalli/nvim-colorizer.lua" = pkgs.vimPlugins.nvim-colorizer-lua.src;
    "purarue/gitsigns-yadm.nvim" = pkgs.fetchFromGitHub {
      owner = "purarue";
      repo = "gitsigns-yadm.nvim";
      rev = "55575b2af68c0c6c73b1c1f8fe7c54e1e7fe8480";
      hash = "sha256-molMbuW1DD+9xCWLY9IQPxow6c8445tumsoUZYXuitw=";
    };
    "Kaiser-Yang/blink-cmp-dictionary" = pkgs.vimPlugins.blink-cmp-dictionary.src;
    "moyiz/blink-emoji.nvim" = pkgs.vimPlugins.blink-emoji-nvim.src;
    "andersevenrud/cmp-tmux" = pkgs.vimPlugins.cmp-tmux.src;
    "chrisgrieser/cmp-nerdfont" = pkgs.fetchFromGitHub {
      owner = "chrisgrieser";
      repo = "cmp-nerdfont";
      rev = "e97482344ebed29093015a18c155057adf5c842b";
      hash = "sha256-alHMwjzYZO5rCgQUUUEcGNkW3PuYJFfGyo531wNw7p4=";
    };
    "dmitmel/cmp-digraphs" = pkgs.vimPlugins.cmp-digraphs.src;
    "lukas-reineke/indent-blankline.nvim" = pkgs.vimPlugins.indent-blankline-nvim.src;
    "obsidian-nvim/obsidian.nvim" = pkgs.vimPlugins.obsidian-nvim.src;
    "cappyzawa/trim.nvim" = pkgs.vimPlugins.trim-nvim.src;
    "ericbn/vim-relativize" = pkgs.fetchFromGitHub {
      owner = "ericbn";
      repo = "vim-relativize";
      rev = "0555753e13d995cdfda2acef015a6ab9c0d81a5f";
      hash = "sha256-0dXHYJlk3fLXVJ0SkkPZNwh4+Vp4SOmS6IS/DOn37h0=";
    };
    "mogelbrod/vim-jsonpath" = pkgs.vimPlugins.vim-jsonpath.src;
    "nvim-tree/nvim-web-devicons" = pkgs.vimPlugins.nvim-web-devicons.src;
    "cuducos/yaml.nvim" = pkgs.fetchFromGitHub {
      owner = "cuducos";
      repo = "yaml.nvim";
      rev = "43ddedd0f3b060b4475e19e762b1796fce1b23be";
      hash = "sha256-2fDNV0usUsGN45igalfVpZ1AXzerwUAOWcXU2/OIgbQ=";
    };
    "nacro90/numb.nvim" = pkgs.vimPlugins.numb-nvim.src;
    "ibhagwan/fzf-lua" = pkgs.vimPlugins.fzf-lua.src;
    "EinfachToll/DidYouMean" = pkgs.fetchFromGitHub {
      owner = "EinfachToll";
      repo = "DidYouMean";
      rev = "a98fb17ba16aa2eb69b3f9cc7a70e8a736890e4e";
      hash = "sha256-lOGxMpIky9+MhRTYxy4EV125ZSmZx/tZpoH58mXBcZ8=";
    };
    "tpope/vim-abolish" = pkgs.vimPlugins.vim-abolish.src;
    "ivyl/vim-bling" = pkgs.fetchFromGitHub {
      owner = "ivyl";
      repo = "vim-bling";
      rev = "5e59a06d14dfc7b44f3d8af109d0a71a107060be";
      hash = "sha256-iJ/uaoq71IM1hQSrnZ86MBlpUWRp9vs1Grd1+9C1QFM=";
    };
    "L3MON4D3/LuaSnip" = pkgs.vimPlugins.luasnip.src;
    "HakonHarnes/img-clip.nvim" = pkgs.vimPlugins.img-clip-nvim.src;
    "romainl/vim-cool" = pkgs.vimPlugins.vim-cool.src;
    "someone-stole-my-name/yaml-companion.nvim" = pkgs.vimPlugins.yaml-companion-nvim.src;
    "navarasu/onedark.nvim" = pkgs.vimPlugins.onedark-nvim.src;
    "benizi/vim-automkdir" = pkgs.vimPlugins.vim-automkdir.src;
    "lambdalisue/suda.vim" = pkgs.vimPlugins.vim-suda.src;
    "tpope/vim-eunuch" = pkgs.vimPlugins.vim-eunuch.src;
    "whatyouhide/vim-lengthmatters" = pkgs.fetchFromGitHub {
      owner = "whatyouhide";
      repo = "vim-lengthmatters";
      rev = "1c4df3b98e4ce7f3f59b76a8fb9d51a12de6f3cc";
      hash = "sha256-UkRrB6A+s5pv+aVxUUT7f2p0FMpPD9VZ+0tP8IMS/xM=";
    };
    "utilyre/barbecue.nvim" = pkgs.vimPlugins.barbecue-nvim.src;
    "nvim-telescope/telescope.nvim" = pkgs.vimPlugins.telescope-nvim.src;
    "mcauley-penney/visual-whitespace.nvim" = pkgs.vimPlugins.visual-whitespace-nvim.src;
    "SmiteshP/nvim-navic" = pkgs.vimPlugins.nvim-navic.src;
    "lewis6991/fileline.nvim" = pkgs.vimPlugins.fileline-nvim.src;
    "google/vim-jsonnet" = pkgs.vimPlugins.vim-jsonnet.src;
    "saghen/blink.compat" = pkgs.vimPlugins.blink-compat.src;
    "ethanholz/nvim-lastplace" = pkgs.vimPlugins.nvim-lastplace.src;
    "kylechui/nvim-surround" = pkgs.vimPlugins.nvim-surround.src;
    "saghen/blink.cmp" = pkgs.vimPlugins.blink-cmp.src;
    "saghen/blink.lib" = pkgs.vimPlugins.blink-lib.src;
    "rafamadriz/friendly-snippets" = pkgs.vimPlugins.friendly-snippets.src;
    "folke/sidekick.nvim" = pkgs.vimPlugins.sidekick-nvim.src;
    "gbprod/yanky.nvim" = pkgs.vimPlugins.yanky-nvim.src;
    "cappyzawa/telescope-terraform.nvim" = pkgs.fetchFromGitHub {
      owner = "cappyzawa";
      repo = "telescope-terraform.nvim";
      rev = "072c97023797ca1a874668aaa6ae0b74425335df";
      hash = "sha256-uXWW7ewAHZlTF1BDpwgCkB4969PD6K1T5kLte5CJvTg=";
    };
    "ANGkeith/telescope-terraform-doc.nvim" = pkgs.fetchFromGitHub {
      owner = "ANGkeith";
      repo = "telescope-terraform-doc.nvim";
      rev = "66987fac94d12704fdfd90b857f4f648e31251c9";
      hash = "sha256-yv+/pabR/Reaj5+DSmHhW/viPdqLlq58bekY1lKVGhE=";
    };
  };
  nvimDevDirName =
    repo: if nvimDevPathFunction then lib.replaceStrings [ "/" ] [ "--" ] repo else baseNameOf repo;
  termuxNvimPluginSpecs =
    assert lib.assertMsg (lib.all (repo: builtins.match "[^/:]+/[^/]+" repo != null) (
      builtins.attrNames termuxNvimPlugins
    )) "termuxNvimPlugins keys must be \"owner/repo\", as in the Lazy specs.";
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (repo: _source: "    { \"${repo}\", dev = true, pin = true },") termuxNvimPlugins
    );
  termuxHomeFiles = homeManagerProfile.config.termux.homeFiles;
  exportedHomeFiles = lib.unique (termuxHomeFiles ++ [ ".local/share/nvim/lazy-dev" ]);
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
      # Store source paths normally; generated files must remain build inputs.
      source =
        let
          fileSource = homeManagerProfile.config.home.file.${sourcePath}.source;
        in
        if builtins.isPath fileSource then
          builtins.path {
            path = fileSource;
            name = builtins.baseNameOf path;
          }
        else
          fileSource;
    }
  ) termuxHomeFiles;
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
            aptLibraries = package.passthru.termuxNative.aptLibraries or [ ];
            runtimeLibraries = package.passthru.termuxNative.runtimeLibraries or [ ];
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
    homeFiles = exportedHomeFiles;
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
  } "bash ${../../../android/termux-native/build-gitstatus.sh}";
  upstreamEnvironment =
    pkgs.runCommand "termux-native-environment"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.jq
          pkgs.patchelf
          elfCleaner
        ];
        allowedReferences = [ ];
      }
      ''
        mkdir -p "$out/bin" "$out/etc/profile.d" "$out/home" "$out/libexec" "$out/shell/plugins"
        cat > "$out/bin/nvim" <<'EOF'
        #!/data/data/com.termux/files/usr/bin/sh
        if [ -n "''${TERMUX_GENERATION:-}" ]; then
          export XDG_CONFIG_HOME="$TERMUX_GENERATION/home/.config"
        fi
        exec /data/data/com.termux/files/usr/bin/nvim "$@"
        EOF
        chmod 755 "$out/bin/nvim"
        ${target.cc} \
          -O2 -Wall -Wextra -Werror -fPIE -pie -Wl,-z,max-page-size=16384 \
          -Wl,-z,common-page-size=16384 \
          ${../../../android/termux-native/hello.c} -o "$out/bin/termux-nix-hello"
        ${target.strip} "$out/bin/termux-nix-hello"
        ${target.readelf} -h -l -d "$out/bin/termux-nix-hello"
        ${target.cc} \
          -O2 -Wall -Wextra -Werror -fPIE -pie -Wl,-z,max-page-size=16384 \
          -Wl,-z,common-page-size=16384 \
          ${../../../android/termux-native/launcher.c} \
          -o "$out/libexec/termux-native-launcher"
        ${target.strip} "$out/libexec/termux-native-launcher"
        ${target.readelf} -h -l -d "$out/libexec/termux-native-launcher"
        cp ${../../../android/termux-native/plugin.zsh} "$out/shell/plugins/example.zsh"
        cp ${../../../android/termux-native/activate.sh} "$out/activate.sh"
        cp ${../../../android/termux-native/setup-known-hosts.sh} "$out/setup-known-hosts.sh"
        chmod 755 "$out/setup-known-hosts.sh"
        cp ${../../../android/termux-native/setup-gpg-keys.sh} "$out/setup-gpg-keys.sh"
        chmod 755 "$out/setup-gpg-keys.sh"
        cp ${../../../android/termux-native/bootstrap.sh} "$out/bootstrap.sh"
        cp ${../../../android/termux-native/zshenv} "$out/zshenv"
        cp ${../../../android/termux-native/smoke-test.zsh} "$out/shell/smoke-test.zsh"
        cp ${../../../android/termux-native/check-pty.zsh} "$out/shell/check-pty.zsh"
        cp ${../../../android/termux-native/prompt.zsh} "$out/shell/prompt.zsh"
        cp ${../../../android/termux-native/check-nvim-plugins.lua} "$out/shell/check-nvim-plugins.lua"
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
        chmod u+w "$out/home"
        mkdir -p "$out/home/.local"
        chmod u+w "$out/home/.local"
        mkdir -p "$out/home/.local/share"
        chmod u+w "$out/home/.local/share"
        mkdir -p "$out/home/.local/share/nvim/lazy-dev"
        # Validate the generated plugin tree during the build, not evaluation.
        test -d ${lib.escapeShellArg nvimLazyPath}
        cp -RL ${nvimDevPath}/. "$out/home/.local/share/nvim/lazy-dev/"
        ${lib.concatMapStringsSep "\n" (repo: ''
          mkdir -p "$out/home/.local/share/nvim/lazy-dev/${nvimDevDirName repo}"
          cp -RL ${termuxNvimPlugins.${repo}}/. "$out/home/.local/share/nvim/lazy-dev/${nvimDevDirName repo}/"
        '') (builtins.attrNames termuxNvimPlugins)}
        chmod -R u+w "$out/home/.local/share/nvim/lazy-dev"
        rm -rf "$out/home/.local/share/nvim/lazy-dev/${nvimDevDirName "L3MON4D3/LuaSnip"}/tests"
        find "$out/home/.local/share/nvim/lazy-dev" -type d -name nix-support -prune -exec rm -rf {} +
        while IFS= read -r -d $'\0' plugin_file; do
          if ! grep -Iq '/nix/store/' "$plugin_file"; then
            continue
          fi
          case "$plugin_file" in
            *.lua)
              sed -i '1{/^#!\/nix\/store\//d;}' "$plugin_file"
              ;;
            *)
              sed -i -E \
                -e '1s|^#!/nix/store/[^/]+/bin/bash.*$|#!/data/data/com.termux/files/usr/bin/bash|' \
                -e '1s|^#!/nix/store/[^/]+/bin/sh.*$|#!/data/data/com.termux/files/usr/bin/sh|' \
                "$plugin_file"
              ;;
          esac
        done < <(find "$out/home/.local/share/nvim/lazy-dev" -type f -print0)
        if grep -RIl '/nix/store/' "$out/home/.local/share/nvim/lazy-dev"; then
          echo "Neovim plugin bundle contains Nix store paths after sanitization." >&2
          exit 1
        fi
        substituteInPlace "$out/home/.local/share/nvim/lazy-dev/${nvimLazyDir}/lua/lazy/help.lua" \
          --replace-fail \
          'vim.cmd.helptags(Config.plugins["lazy.nvim"].dir .. "/doc")' \
          '-- Termux plugin sources are immutable; their helptags are not regenerated.'
        substituteInPlace "$out/home/.config/nvim/init.lua" \
          --replace-fail ${lib.escapeShellArg nvimLazyAssignment} \
          ${lib.escapeShellArg "local lazypath = vim.env.TERMUX_GENERATION .. \"/home/.local/share/nvim/lazy-dev/${nvimLazyDir}\""}
        ${
          if nvimDevPathFunction then
            ''
              substituteInPlace "$out/home/.config/nvim/init.lua" \
                --replace-fail ${lib.escapeShellArg "\"${nvimDevPath}/\""} \
                  ${lib.escapeShellArg "vim.env.TERMUX_GENERATION .. \"/home/.local/share/nvim/lazy-dev/\""}
            ''
          else
            ''
              substituteInPlace "$out/home/.config/nvim/init.lua" \
                --replace-fail ${lib.escapeShellArg "path = \"${nvimDevPath}\""} \
                  ${lib.escapeShellArg "path = function(plugin) return vim.env.TERMUX_GENERATION .. \"/home/.local/share/nvim/lazy-dev/\" .. vim.fn.fnamemodify(plugin.name, \":t\") end"}
            ''
        }
        substituteInPlace "$out/home/.config/nvim/init.lua" \
          --replace-fail ${lib.escapeShellArg "patterns = {},  -- Don't automatically match, use explicit dev = true"} \
          ${lib.escapeShellArg "patterns = { \"\" }, -- Use the bundled local plugin sources"} \
          --replace-fail ${lib.escapeShellArg "  -- User plugins"} \
          ${lib.escapeShellArg "  -- Nix-managed Termux plugin sources\n${termuxNvimPluginSpecs}\n  -- User plugins"} \
          --replace-fail ${lib.escapeShellArg "require(\"lazy\").setup({"} \
          ${lib.escapeShellArg "vim.fn.mkdir(vim.fn.stdpath(\"state\"), \"p\")\nrequire(\"lazy\").setup({"} \
          --replace-fail ${lib.escapeShellArg "  install = { colorscheme = { \"tokyonight\", \"habamax\" } },"} \
          ${lib.escapeShellArg "  lockfile = vim.fn.stdpath(\"state\") .. \"/lazy-lock.json\",\n  install = { missing = false, colorscheme = { \"tokyonight\", \"habamax\" } },"} \
          --replace-fail ${lib.escapeShellArg "  performance = {"} \
          ${lib.escapeShellArg "  performance = {\n    cache = { enabled = false },"}
        # Every dev spec must resolve to a bundled source, using the directory
        # name Lazy's dev path function derives from the repository.
        spec_count=0
        while IFS= read -r repo; do
          spec_count=$((spec_count + 1))
          ${if nvimDevPathFunction then ''dir="''${repo//\//--}"'' else ''dir="''${repo##*/}"''}
          if [ ! -d "$out/home/.local/share/nvim/lazy-dev/$dir" ]; then
            echo "Neovim dev spec $repo has no bundled source: lazy-dev/$dir" >&2
            exit 1
          fi
        done < <(sed -nE 's|^[[:space:]]*\{ "([^"/:]+/[^"]+)", (import = "[^"]+", )?dev = true.*|\1|p' "$out/home/.config/nvim/init.lua")
        if [ "$spec_count" -lt ${toString (builtins.length (builtins.attrNames termuxNvimPlugins))} ]; then
          echo "Neovim init.lua lists too few dev specs ($spec_count)." >&2
          exit 1
        fi
        while IFS= read -r -d $'\0' plugin_file; do
          if ${target.readelf} -h "$plugin_file" >/dev/null 2>&1; then
            echo "Neovim plugin bundle contains a non-Termux ELF: $plugin_file" >&2
            exit 1
          fi
        done < <(find "$out/home/.local/share/nvim/lazy-dev" -type f -print0)
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
        bash ${../../../android/termux-native/export-home-packages.sh} \
          ${termuxNativePackageManifest} \
          "$out" \
          ${target.readelf} \
          ${target.sysrootLib} \
          ${pkgs.patchelf}/bin/patchelf \
          ${elfCleaner}/bin/termux-elf-cleaner \
          ${toString apiLevel}
      '';
  environment =
    if termuxpp then
      pkgs.runCommand "termuxpp-native-environment" { allowedReferences = [ ]; } ''
        cp -a ${upstreamEnvironment} "$out"
        chmod -R u+w "$out"
        ${pkgs.python3}/bin/python3 -I ${../../../android/termux-native/relocate-termuxpp.py} "$out"
      ''
    else
      upstreamEnvironment;
  bundle =
    pkgs.runCommand "${if termuxpp then "termuxpp" else "termux"}-native-bundle"
      { allowedReferences = [ ]; }
      ''
        mkdir -p "$out"
        tar --hard-dereference --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -C ${environment} -cf - . | gzip -n > "$out/environment.tar.gz"
        cd "$out"
        sha256sum environment.tar.gz > SHA256SUMS
        cp ${environment}/activate.sh ${environment}/bootstrap.sh "$out/"
        cp ${environment}/manifest.json "$out/manifest.json"
      '';
in
{
  inherit bundle environment gitstatus;
}
