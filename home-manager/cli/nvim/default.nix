{
  config,
  inputs,
  lib,
  options,
  pkgs,
  ...
}:
let
  # The same Nixvim configuration, built around the nightly binary and with
  # the config wrapped into the package (nvim-nightly must not pick up the
  # stable init.lua from ~/.config/nvim).
  nvimNightly =
    (options.programs.nixvim.valueMeta.configuration.extendModules {
      modules = [
        {
          package = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.neovim;
          wrapRc = true;
          # Keep ~/.config/nvim on the runtimepath for lua/local/
          impureRtp = true;
        }
      ];
    }).config.build.package;
in
{
  imports = [ inputs.nixvim.homeModules.nixvim ];

  options.programs.neovim.nightly.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install the additional nvim-nightly command alongside configured Neovim.";
  };

  config = {
    programs.nixvim = {
      enable = true;
      # Our pkgs: overlays (e.g. the TermuxPP neovim patch) and allowUnfree
      # (copilot-language-server)
      nixpkgs.useGlobalPackages = true;
      imports = [ ./nixvim ];
    };

    home.packages = lib.optionals config.programs.neovim.nightly.enable [
      (pkgs.runCommand "nvim-nightly" { } ''
        mkdir -p $out/bin
        ln -s ${nvimNightly}/bin/nvim $out/bin/nvim-nightly
      '')
    ];
  };
}
