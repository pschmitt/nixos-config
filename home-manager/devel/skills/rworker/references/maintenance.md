# Maintaining rworker

The client's `spec()` (`rworker __spec`) drives the zsh and bash
completions. When adding an action or flag, update `spec()`, the dispatch in
`main()` and `action_help()` together; the flake check `rworker-completions`
(`scripts/check-spec.sh`) fails otherwise.
