# Maintaining rworker

The client's `spec()` (`rworker __spec`) drives the zsh and bash
completions. When adding an action or flag, update `spec()`, the dispatch in
`main()` and `action_help()` together; the flake check `rworker-completions`
(`scripts/check-spec.sh`) fails otherwise.

The worker image is the NixOS host `rworker` (`hosts/rworker/`, flake output
`images.rworker`, boot check `rworker-boot`; formerly `nixbot-worker`). The
kernel command line parameter `nixbot-worker.metadata` and the OpenStack
server metadata key `nixbot-worker` are a protocol with the control host and
keep their old names. The publish effect keeps its name
`publish-nixbot-worker-image`.

After changing the worker image, a successful build or cache upload does not
mean it is published in Glance. Verify the `publish-nixbot-worker-image`
effect and smoke-test a fresh `up`: existing workers keep their original
image. In particular, token installation reports `image-too-old` until the
published image supplies `/run/rworker-niks3`; patching an existing worker
can test the issuer but does not validate image rollout.
