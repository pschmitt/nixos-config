{
  inputs,
  final,
  prev,
}:
let
  # TODO remove once https://github.com/NixOS/nixpkgs/pull/436619
  # is merged!
  pkgs114 = import inputs.nixpkgs-rbw-114 {
    inherit (final) system;
    overlays = [ ]; # keep it clean to avoid recursion
  };

  fullPatch = final.fetchpatch {
    url = "https://github.com/doy/rbw/compare/1.14.0...pschmitt:json-1.14.patch";
    hash = "sha256-yMyxGAsqUXt0ipXGSa+TYTMOXSRlNkrNg09cZRLYCv0=";
  };
in
{
  rbw = pkgs114.rbw.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ fullPatch ];
  });
}
