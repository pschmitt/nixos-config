final: prev: {
  # Codex 0.169.1 uses openssl-sys but its package omits OpenSSL headers.
  # Local workaround: remove when llm-agents.nix supplies the dependency.
  # Reviewed 2026-11-18 at Nixpkgs 1a08097fc1ed85575db39763b2c4a5d8970a37ba;
  # the unpatched build fails to find openssl.pc.
  llm-agents = prev.llm-agents // {
    codex = prev.llm-agents.codex.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ final.openssl ];
    });
  };
}
