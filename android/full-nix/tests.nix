{ inputs }:
let
  homes = import ./. { inherit inputs; };
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
    assert c.home.homeDirectory == "/home/nix";
    assert c.home.username == "nix";
    assert c.termux.enable == false;
    assert c.termux.packages == [ ];
    assert c.programs.zsh.enable;
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
