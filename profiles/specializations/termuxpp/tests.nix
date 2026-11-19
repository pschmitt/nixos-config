{ inputs }:
let
  homes = import ./homes.nix { inherit inputs; };
  check =
    hostname: home:
    let
      c = home.config;
      expectedColor =
        {
          zf10 = "080";
          p11 = "246";
        }
        .${hostname};
    in
    assert c.home.homeDirectory == "/home/pschmitt";
    assert c.home.username == "pschmitt";
    assert builtins.all (p: builtins.elem p c.home.packages) [
      home.pkgs.openstackclient-full
      home.pkgs.kubectl
      home.pkgs.kubernetes-helm
      home.pkgs.opentofu
      home.pkgs.ansible
    ];
    assert builtins.elem home.pkgs.jc c.home.packages;
    assert c.fullNix.androidBridge.enable;
    assert c.fullNix.lifecycle.enable;
    assert builtins.elem "writeBoundary" c.home.activation.androidPreflight.before;
    assert builtins.elem "linkGeneration" c.home.activation.androidAcceptance.after;
    assert builtins.elem "onFilesChange" c.home.activation.androidAcceptance.after;
    assert builtins.elem "installPackages" c.home.activation.androidAcceptance.after;
    assert c.programs.home-manager.enable;
    assert builtins.match "file:///nix/store/.*" c.nix.settings.flake-registry != null;
    assert c.fullNix.rworker.enable;
    assert c.fullNix.rworker.controller == null;
    assert c.fullNix.rworker.system == "aarch64-linux";
    assert c.programs.eza.package.name == "eza-full-nix";
    assert builtins.elem c.programs.eza.package c.home.packages;
    assert c.programs.eza.package == home.pkgs.eza;
    assert home.pkgs.bat.fullNixSignalStackPrograms == [ "bat" ];
    assert home.pkgs.fd.fullNixSignalStackPrograms == [ "fd" ];
    assert home.pkgs.ripgrep.fullNixSignalStackPrograms == [ "rg" ];
    assert
      home.pkgs.rbw.fullNixSignalStackPrograms == [
        "rbw"
        "rbw-agent"
      ];
    assert home.pkgs.openstack-rs.fullNixSignalStackPrograms == [ "osc" ];
    assert home.pkgs.vivid.fullNixSignalStackPrograms == [ "vivid" ];
    assert home.pkgs.zoxide.fullNixSignalStackPrograms == [ "zoxide" ];
    assert builtins.elem ../../../overlays/termuxpp/rsync-search-only-ancestors.patch
      home.pkgs.rsync.patches;
    assert c.nix.settings.max-jobs == 0;
    assert c.nix.settings.builders-use-substitutes;
    assert c.nix.registry.nixpkgs.to.type == "path";
    assert c.nix.nixPath == [ "nixpkgs=${c.nix.registry.nixpkgs.to.path}" ];
    assert builtins.any (p: (p.pname or "") == "iputils") c.home.packages;
    assert c.home.sessionVariables.NIX_CONF_DIR == "/home/pschmitt/.config/nix";
    assert c.termux.enable == false;
    assert c.termux.packages == [ ];
    assert c.programs.zsh.enable;
    assert c.programs.zsh.dotDir == "/home/pschmitt/.config/zsh";
    # ZDOTDIR comes from the guest /etc/zshenv (systems.nix), not ~/.zshenv.
    assert !c.home.file.".zshenv".enable;
    assert c.dotfiles.zsh.nixShell.default;
    assert c.programs.neovim.enable;
    assert !c.programs.neovim.nightly.enable;
    assert c.programs.lazyvim.appName == "nvim";
    assert builtins.any (p: (p.pname or "") == "nixd") c.programs.neovim.extraPackages;
    assert builtins.any (p: (p.pname or "") == "statix") c.programs.neovim.extraPackages;
    assert c.programs.zsh.package.stdenv.hostPlatform.system == "aarch64-linux";
    assert c.programs.tmux.shell == "${home.pkgs.zsh}/bin/zsh";
    assert c.systemd.user.startServices == false;
    assert c.home.sessionVariables.HOST == hostname;
    assert c.dotfiles.promptColor == expectedColor;
    assert builtins.all (p: p.stdenv.hostPlatform.system == "aarch64-linux") c.home.packages;
    {
      inherit hostname;
      activation = home.activationPackage.drvPath;
      shell = "${home.pkgs.zsh}/bin/zsh";
      packageCount = builtins.length c.home.packages;
    };
in
builtins.mapAttrs check homes
