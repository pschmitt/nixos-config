{ pkgs, ... }:
{
  # fzf can crash in the guest's Go scheduler with multiple processors.
  programs.fzf.package = pkgs.symlinkJoin {
    name = "fzf-zf10";
    paths = [ pkgs.fzf ];
    inherit (pkgs.fzf) meta;
    passthru = { inherit (pkgs.fzf) version; };
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/fzf" --set GOMAXPROCS 1
    '';
  };
}
