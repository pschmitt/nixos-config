final: prev: {
  # Codex 0.167.0 uses openssl-sys but its package omits OpenSSL headers.
  # Local workaround: remove when llm-agents.nix supplies the dependency.
  # Reviewed 2026-11-10 at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6;
  # the unpatched build fails to find openssl.pc; the patched build succeeds.
  llm-agents = prev.llm-agents // {
    codex = prev.llm-agents.codex.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ final.openssl ];
    });
  };
}
