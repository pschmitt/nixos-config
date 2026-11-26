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
      configFiles = builtins.attrNames c.xdg.configFile;
      # A local zsh topic ships its plugin or function files
      zshTopicShipped =
        topic:
        builtins.any (
          name:
          name == "zsh/plugins/local/${topic}.zsh"
          ||
            builtins.substring 0 (builtins.stringLength "zsh/functions/${topic}/") name
            == "zsh/functions/${topic}/"
        ) configFiles;
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
    assert c.nixpp.androidBridge.enable;
    assert c.nixpp.lifecycle.enable;
    assert builtins.elem "writeBoundary" c.home.activation.androidPreflight.before;
    assert builtins.elem "linkGeneration" c.home.activation.androidAcceptance.after;
    assert builtins.elem "onFilesChange" c.home.activation.androidAcceptance.after;
    assert builtins.elem "installPackages" c.home.activation.androidAcceptance.after;
    assert c.programs.home-manager.enable;
    assert builtins.match "file:///nix/store/.*" c.nix.settings.flake-registry != null;
    assert c.nixpp.rworker.enable;
    assert c.nixpp.rworker.controller != null;
    assert c.nixpp.rworker.awsCredentialsFile == c.nixpp.upgradeCache.credentials_file;
    assert c.nixpp.rworker.system == "aarch64-linux";
    assert c.programs.eza.package.name == "eza-nixpp";
    assert builtins.elem c.programs.eza.package c.home.packages;
    assert c.programs.eza.package == home.pkgs.eza;
    assert home.pkgs.bat.nixppSignalStackPrograms == [ "bat" ];
    assert home.pkgs.fd.nixppSignalStackPrograms == [ "fd" ];
    assert home.pkgs.rworker.nixppSignalStackPrograms == [ "rworker" ];
    assert
      (home.pkgs.rworker.override { sshControlMaster = false; }).nixppSignalStackPrograms == [
        "rworker"
      ];
    assert home.pkgs.ripgrep.nixppSignalStackPrograms == [ "rg" ];
    assert
      home.pkgs.rbw.nixppSignalStackPrograms == [
        "rbw"
        "rbw-agent"
      ];
    assert home.pkgs.openstack-rs.nixppSignalStackPrograms == [ "osc" ];
    assert home.pkgs.vivid.nixppSignalStackPrograms == [ "vivid" ];
    assert home.pkgs.zoxide.nixppSignalStackPrograms == [ "zoxide" ];
    assert builtins.elem ../../../overlays/termuxpp/rsync-search-only-ancestors.patch
      home.pkgs.rsync.patches;
    assert c.nix.settings.max-jobs == 0;
    assert c.nix.settings.builders-use-substitutes;
    assert builtins.elem c.nix.package c.home.packages;
    assert c.nix.package == home.pkgs.nix || !(builtins.elem home.pkgs.nix c.home.packages);
    assert c.nix.registry.nixpkgs.to.type == "path";
    assert
      c.nix.registry.termuxPkgs.to == {
        type = "path";
        path = toString inputs.termuxpp.outPath;
      };
    assert c.nix.nixPath == [ "nixpkgs=${c.nix.registry.nixpkgs.to.path}" ];
    assert builtins.any (p: (p.pname or "") == "iputils") c.home.packages;
    assert c.home.sessionVariables.NIX_CONF_DIR == "/home/pschmitt/.config/nix";
    assert c.programs.zsh.enable;
    assert c.programs.zsh.dotDir == "/home/pschmitt/.config/zsh";
    # ZDOTDIR comes from the guest /etc/zshenv (systems.nix), not ~/.zshenv.
    assert !c.home.file.".zshenv".enable;
    assert c.dotfiles.zsh.nixShell.default;
    # No systemd, NixOS system or desktop session on the phones: their local
    # zsh topics are excluded (programs.zsh.localConfig.excludeTopics).
    assert
      !builtins.any zshTopicShipped [
        "bootctl"
        "hyprland"
        "journald"
        "nixos"
        "systemd"
        "udev"
        "wayland"
      ];
    assert zshTopicShipped "tmux" && zshTopicShipped "git";
    assert builtins.elem "zsh/plugins/local.zsh" configFiles;
    assert c.programs.nixvim.enable;
    assert !c.programs.neovim.nightly.enable;
    assert c.programs.nixvim.lsp.servers.nixd.enable;
    assert !c.programs.nixvim.lsp.servers.nil_ls.enable;
    assert builtins.any (p: (p.pname or "") == "statix") c.programs.nixvim.extraPackages;
    assert c.programs.zsh.package.stdenv.hostPlatform.system == "aarch64-linux";
    assert !c.programs.tmux.enable;
    assert
      c.xdg.configFile."tmux/local.conf".text == ''
        set -g default-shell ${home.pkgs.zsh}/bin/zsh
      '';
    assert c.xdg.configFile."tmux/plugins-nix.conf".text != "";
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
