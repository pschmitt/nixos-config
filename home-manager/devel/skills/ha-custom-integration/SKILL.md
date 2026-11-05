---
name: ha-custom-integration
description: Use when creating, publishing, updating or documenting a Home Assistant custom integration repository, including HACS/Marketplace setup, branding, README badges, catalog submission and release checks.
---

# Home Assistant custom integration

Use this checklist for an integration's **public GitHub repository**. For a
configuration-repo submodule or live HA deployment, also load `ha` and follow
that repository's `AGENTS.md`; for the public README, load `readme`. Never put
instance URLs, tokens, real account data or private infrastructure in the
integration repository or its screenshots.

## Create the repository

1. Choose a stable, unique integration `domain`. Create one public repository
   for that integration, with a GitHub description, relevant topics and issues
   enabled. Keep the source at `custom_components/<domain>/`; the directory and
   `manifest.json` domain must agree.
2. Include a valid `manifest.json` with `domain`, `name`, `version`,
   `documentation`, `issue_tracker` and `codeowners`; include a root `hacs.json`
   with `name`. Point documentation and issue links at the repository that will
   actually be published, especially after forking.
3. Add branding before release: put at least
   `custom_components/<domain>/brand/icon.png` in the repository, or provide
   domain-specific assets in the Home Assistant brands repository. Check image
   legibility in light and dark themes and licensing of third-party marks.
4. Write a short root `README.md` with a concrete description, features,
   installation, first-run configuration and a license link if licensed.
   Follow `readme`; put long options, examples and troubleshooting in `docs/`.
   Verify every relative link. Add a `LICENSE` when distributing under a
   license; do not invent one when adapting upstream code.
5. If this repository is used as a submodule, add it to the HA configuration
   repository and follow its symlink/deploy conventions. Edit the authored
   source, not a symlinked installation. Do not treat a submodule checkout as
   the canonical GitHub release.

## Install badge and catalog

For an integration, add this direct-install badge to the README, substituting
the **origin** GitHub owner and repository (not an upstream fork):

```markdown
[![Open this integration in Home Assistant Marketplace](https://my.home-assistant.io/badges/marketplace_repository.svg)](https://my.home-assistant.io/redirect/marketplace_repository/?owner=OWNER&repository=REPOSITORY&category=integration)
```

The Marketplace link requires Home Assistant 2026.11 or later. It can register
an unlisted repository as a custom repository; do not describe the badge as
proof of public catalog inclusion. For older installations, document the HACS
custom-repository flow if needed. Replace obsolete `hacs_repository` badges
when refreshing installation docs.

For **public catalog listing** (not needed for direct custom installation):
run both [hassfest](https://github.com/home-assistant/actions) and the
[HACS action](https://github.com/hacs/action) without exclusions; publish a
GitHub **release**, not just a tag; verify repository metadata, manifest,
`hacs.json`, and branding. Then follow the
[Marketplace catalog guide](https://contributors.home-assistant.io/marketplace/guides/catalog/)
for the owner/contributor submission to `hacs/default`. Do not claim listing
before acceptance.

## Before announcing a change

- Validate the integration on the supported HA version and run its existing
  tests and formatting/lint checks. Bound network I/O and avoid blocking HA
  startup with first polls or long-lived tasks; follow the hosting config's
  startup guidance.
- Test installation from the actual release or repository, config flow and
  restart. Check that README instructions and badge resolve to the intended
  repository. Review `git diff` and keep unrelated submodule changes out of
  the release.
- If this integration needs a HA instance restart, coordinate it separately
  from the repository documentation change.
