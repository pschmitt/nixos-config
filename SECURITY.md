# Security Policy

This is a personal NixOS configuration, published to read and borrow from. It
is not a product and has no releases: only the latest commit on `main` is
maintained.

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue or pull
request.

- Use GitHub's [private vulnerability reporting](https://github.com/pschmitt/nixos-config/security/advisories/new)
  for this repository.
- If that is not available to you, email <philipp@schmitt.co>.

Include what you found, where (file and line, or the module and option), and
how it can be exploited. A proof of concept helps but is not required.

This is a one-person project: expect an answer within about a week, and a fix
or a decision on a best-effort basis. Please give me a reasonable time to fix
the issue before disclosing it publicly.

## What is in scope

- Secrets, tokens, keys or private infrastructure details that were committed
  to this repository by mistake (this repository must hold none).
- Insecure defaults or mistakes in the modules, profiles and services here that
  could harm someone who copies them.
- Weaknesses in the CI workflows or scripts in this repository (for example
  injection, or excessive token permissions).

## What is out of scope

- Vulnerabilities in upstream software (nixpkgs, Home Manager, NixOS modules or
  the packaged applications). Report those to the respective project.
- Issues that need prior access to one of the machines this configuration
  deploys to.
- Findings against the private infrastructure itself. Do not probe hosts or
  services; reports must be based on the contents of this repository.

## If you find a leaked secret

Do not use it. Report it as described above, and I will rotate it and clean up
the history if needed.
