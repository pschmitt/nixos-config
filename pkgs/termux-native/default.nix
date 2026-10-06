args:
let
  mkTermuxBundle =
    {
      modules ? [ ],
      extraSpecialArgs ? { },
    }:
    import ./mkTermuxBundle.nix (args // { inherit modules extraSpecialArgs; });
in
(mkTermuxBundle { }) // { inherit mkTermuxBundle; }
