{ pkgs, ... }:
{
  # fzf can crash in the guest's Go scheduler with multiple processors.
  programs.fzf.package = pkgs.symlinkJoin {
    name = "fzf-zf10";
    paths = [
      pkgs.fzf
      pkgs.fzf.man
    ];
    meta = pkgs.fzf.meta // {
      outputsToInstall = [ "out" ];
    };
    passthru = { inherit (pkgs.fzf) version; };
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/fzf" --set GOMAXPROCS 1
    '';
  };
}
