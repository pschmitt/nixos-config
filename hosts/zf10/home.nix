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

  # Go's GC corrupts memory under this phone's guest runtime (Android 15,
  # kernel 5.15): the sops-nix installer crashes or runs away without this.
  nixpp.sops.disableGoGc = true;

  # A double tap on the terminal opens the session sidebar.
  nixpp.settings.gestures.tap.double.action = "open-sidebar";
}
