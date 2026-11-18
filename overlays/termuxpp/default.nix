final: prev:
let
  signalStack = final.stdenv.mkDerivation {
    pname = "full-nix-eza-signal-stack";
    version = "1";
    src = ./eza-stack.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall -Wextra -Werror "$src" -o stack.so
    '';
    installPhase = ''
      install -Dm755 stack.so $out/lib/stack.so
    '';
  };
  withSignalStack =
    package: programs:
    final.symlinkJoin {
      name = "${package.pname or package.name}-full-nix";
      paths = [ package ];
      passthru = {
        fullNixSignalStackPrograms = programs;
      }
      // final.lib.optionalAttrs (package ? version) { inherit (package) version; };
      nativeBuildInputs = [ final.makeWrapper ];
      postBuild = final.lib.concatMapStringsSep "\n" (program: ''
        wrapProgram $out/bin/${program} --prefix LD_PRELOAD : ${signalStack}/lib/stack.so
      '') programs;
    };
in
{
  eza = withSignalStack prev.eza [ "eza" ];
  bat = withSignalStack prev.bat [ "bat" ];
  fd = withSignalStack prev.fd [ "fd" ];
  ripgrep = withSignalStack prev.ripgrep [ "rg" ];
  # The Pixel's seccomp pathname handler overflows nix-locate's Rust signal stack.
  nix-index-unwrapped = withSignalStack prev.nix-index-unwrapped [
    "nix-index"
    "nix-locate"
  ];
  # A channel is not available in the managed guest. Keep comma on the
  # pinned flake registry even when other tools export a NIX_PATH entry.
  comma = prev.comma.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      for program in comma ,; do
        wrapProgram "$out/bin/$program" --unset NIX_PATH
      done
    '';
  });
  rbw = withSignalStack prev.rbw [
    "rbw"
    "rbw-agent"
  ];
  openstack-rs = withSignalStack prev.openstack-rs [ "osc" ];
  vivid = withSignalStack prev.vivid [ "vivid" ];
  zoxide = withSignalStack prev.zoxide [ "zoxide" ];
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
