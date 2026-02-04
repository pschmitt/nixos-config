{
  prev,
  ...
}:

{
  go-task = prev.go-task.overrideAttrs (old: {
    doInstallCheck = false;
    nativeInstallCheckInputs = [ ];

    postInstall = (old.postInstall or "") + ''
      # Use go-task as the canonical binary name (avoid clashing with taskwarrior)
      mv "$out/bin/task" "$out/bin/go-task"

      # Zsh completion: rename file and function to _go-task and target go-task
      mv "$out/share/zsh/site-functions/_task" "$out/share/zsh/site-functions/_go-task"
      substituteInPlace "$out/share/zsh/site-functions/_go-task" \
        --replace "task" "go-task"

      # Bash completion
      mv "$out/share/bash-completion/completions/task.bash" \
        "$out/share/bash-completion/completions/go-task.bash"
      substituteInPlace "$out/share/bash-completion/completions/go-task.bash" \
        --replace "task" "go-task"

      # Fish completion
      mv "$out/share/fish/vendor_completions.d/task.fish" \
        "$out/share/fish/vendor_completions.d/go-task.fish"
      substituteInPlace "$out/share/fish/vendor_completions.d/go-task.fish" \
        --replace "task" "go-task"
    '';
  });
}
