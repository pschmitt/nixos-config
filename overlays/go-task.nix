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
      if [ -x $out/bin/task ]; then
        mv $out/bin/task $out/bin/go-task
      fi
      rm -f $out/bin/task
      # Clean up dangling symlink if present
      if [ -L $out/bin/go-task ] && [ "$(readlink $out/bin/go-task)" = "task" ]; then
        rm $out/bin/go-task
      fi

      # Zsh completion: rename file and function to _go-task and target go-task
      if [ -f $out/share/zsh/site-functions/_task ]; then
        mv $out/share/zsh/site-functions/_task $out/share/zsh/site-functions/_go-task
        substituteInPlace $out/share/zsh/site-functions/_go-task \
          --replace-fail "#compdef task" "#compdef go-task" \
          --replace-fail "compdef _task task" "compdef _go-task go-task" \
          --replace-fail "cmd=(task)" "cmd=(go-task)" \
          --replace-fail "__task_list" "__go_task_list" \
          --replace-fail "_task()" "_go-task()" \
          --replace-fail "_task \"\$@\"" "_go-task \"\$@\"" \
          --replace-fail '"$funcstack[1]" = "_task"' '"$funcstack[1]" = "_go-task"'
      fi

      # Bash completion
      if [ -f $out/share/bash-completion/completions/task.bash ]; then
        mv $out/share/bash-completion/completions/task.bash \
          $out/share/bash-completion/completions/go-task
        substituteInPlace $out/share/bash-completion/completions/go-task \
          --replace-fail "_task()" "_go_task()" \
          --replace-fail "complete -F _task task" "complete -F _go_task go-task"
      fi

      # Fish completion
      if [ -f $out/share/fish/vendor_completions.d/task.fish ]; then
        mv $out/share/fish/vendor_completions.d/task.fish \
          $out/share/fish/vendor_completions.d/go-task.fish
        substituteInPlace $out/share/fish/vendor_completions.d/go-task.fish \
          --replace-fail 'set -l GO_TASK_PROGNAME task' 'set -l GO_TASK_PROGNAME go-task'
      fi
    '';
  });
}
