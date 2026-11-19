# Maintaining rworker

Where the code lives:

- Client, completions, MCP server, Home Manager module and tests: the
  repository [pschmitt/rworker](https://github.com/pschmitt/rworker)
  (Rust; flake input `rworker`). It is `pkgs.rworker`
  (`pkgs.rworker.mcp` for the MCP server), configured through
  `programs.rworker` (`home-manager/devel/rworker.nix`); TermuxPP and
  browser-daemon's provider override it (`extraRuntimeInputs`,
  `sshControlMaster`). Its `AGENTS.md` and `PARITY.md` say how to change it.
- Control host side (`rworker` on rofl-10): `services/scripts/nixbot-workers.py`
  in the private repository.
- On the worker: `hosts/rworker/` (image, `scripts/rworker-metadata.sh`).
- This skill directory holds only the instructions.

Changes to the client go to its repository, then the `deploy` skill (bump
the `rworker` input). Its spec (`rworker __spec`) drives the completions;
`cargo test` there checks the spec, dispatch, help and completion scripts
against each other.

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
