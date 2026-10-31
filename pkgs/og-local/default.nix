{
  lib,
  stdenv,
  fetchurl,
  og-local-model,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "og-local";
  # renovate: datasource=github-releases depName=outgate-ai/og-local
  version = "0.5.2";

  # The redacting build links the ONNX runtime via cgo; `go install` only
  # yields a passthrough build, so use the release archive.
  src = fetchurl {
    url = "https://github.com/outgate-ai/og-local/releases/download/v${finalAttrs.version}/ogl_${finalAttrs.version}_linux_amd64.tar.gz";
    hash = "sha256-p4ELlQXsOgcfZyg5VfG1CdXrNxL52vvGz0dTg8XqCAI=";
  };

  sourceRoot = ".";

  # patchelf and strip both corrupt the prebuilt Go binary (it segfaults on
  # start), so it is kept untouched and started through the Nix glibc loader.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ogl $out/libexec/og-local/ogl
    install -Dm755 lib/libonnxruntime.so $out/lib/libonnxruntime.so

    # ogl picks the agent from argv[0], hence --argv0 "$0" and the symlinks
    mkdir -p $out/bin
    cat > $out/bin/ogl <<WRAPPER
    #!${runtimeShell}
    export OGL_CACHE_DIR="\''${OGL_CACHE_DIR:-${og-local-model}}"
    export OGL_ONNXRUNTIME_LIB="\''${OGL_ONNXRUNTIME_LIB:-$out/lib/libonnxruntime.so}"
    exec ${stdenv.cc.bintools.dynamicLinker} \
      --library-path ${
        lib.makeLibraryPath [
          stdenv.cc.cc.lib
          stdenv.cc.libc
        ]
      } \
      --argv0 "\$0" $out/libexec/og-local/ogl "\$@"
    WRAPPER
    chmod +x $out/bin/ogl
    ln -s ogl $out/bin/ogl-claude
    ln -s ogl $out/bin/ogl-codex

    runHook postInstall
  '';

  meta = {
    description = "Local privacy proxy that redacts PII and secrets from coding-agent prompts";
    homepage = "https://github.com/outgate-ai/og-local";
    license = lib.licenses.bsl11;
    mainProgram = "ogl";
    platforms = [ "x86_64-linux" ];
  };
})
