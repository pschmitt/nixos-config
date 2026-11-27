final: prev:
let
  flakeComma = prev.comma.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      for program in comma ,; do
        wrapProgram "$out/bin/$program" --unset NIX_PATH
      done
    '';
  });
in
{
  # A channel is not available in the managed guest. Keep comma on the
  # pinned flake registry even when other tools export a NIX_PATH entry.
  comma = flakeComma;
  ssh-clipboard = prev.ssh-clipboard.overrideAttrs (old: {
    patches = old.patches ++ [ ../../pkgs/ssh-clipboard/termuxpp-backend.patch ];
  });
  # The guest cannot reliably allocate LuaJIT executable memory at startup.
  # The patch only touches the test suite: two treesitter tests assumed async parses finish
  # within their 3ms budget, which does not hold when the build runs under emulation.
  #
  # `self` must point at the overridden interpreter: luajit derives `pkgs`/`withPackages` (which
  # neovim's runtime Lua environment, and therefore the linked libluajit, come from) from its
  # `self` argument, which otherwise stays the stock JIT-enabled luajit.
  neovim-unwrapped =
    let
      luajitNoJit = prev.luajit.override {
        enableJIT = false;
        self = luajitNoJit;
      };
    in
    (prev.neovim-unwrapped.override {
      luajit = luajitNoJit;
    }).overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./neovim-treesitter-async-tests.patch ];
      });
  rsync = prev.rsync.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./rsync-search-only-ancestors.patch ];
  });
  iputils = prev.iputils.overrideAttrs (old: {
    mesonFlags = old.mesonFlags ++ [ "-DUSE_CAP=false" ];
  });
}
