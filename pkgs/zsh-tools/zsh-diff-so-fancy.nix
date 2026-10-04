{
  lib,
  stdenvNoCC,
  zsh,
  inputs,
}:
let
  src = inputs.zsh-diff-so-fancy;
  pluginDir = "share/zsh/plugins/zsh-diff-so-fancy";
in
stdenvNoCC.mkDerivation {
  pname = "zsh-diff-so-fancy";
  version = "unstable-2026-08-21";
  inherit src;
  nativeBuildInputs = [ zsh ];
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p "$out/bin"
    install -Dm644 "$src/zsh-diff-so-fancy.plugin.zsh" \
      "$out/${pluginDir}/zsh-diff-so-fancy.plugin.zsh"
    install -Dm755 "$src/bin/git-dsf" "$out/${pluginDir}/bin/git-dsf"
    install -Dm755 "$src/bin/fancy-diff" "$out/${pluginDir}/bin/fancy-diff"
    ln -s "$out/${pluginDir}/bin/git-dsf" "$out/bin/git-dsf"
    ln -s "$out/${pluginDir}/bin/fancy-diff" "$out/bin/fancy-diff"
  '';

  meta = {
    description = "Zsh integration for diff-so-fancy";
    homepage = "https://github.com/z-shell/zsh-diff-so-fancy";
    mainProgram = "git-dsf";
    platforms = lib.platforms.unix;
  };
}
