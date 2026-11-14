args:
let
  mkTermuxBundle =
    {
      modules ? [ ],
      extraSpecialArgs ? { },
      termuxpp ? false,
    }:
    import ./mkTermuxBundle.nix (args // { inherit modules extraSpecialArgs termuxpp; });
in
(mkTermuxBundle { }) // { inherit mkTermuxBundle; }
