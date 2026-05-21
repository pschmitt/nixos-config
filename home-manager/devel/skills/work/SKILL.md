---
name: work
description: Use for work-related tasks at wiit.cloud — navigating repos, understanding team structure, GitLab, or anything spanning the EDGE or CKS teams. References the jira and confluence skills for issue and wiki work.
---

# Work

Use this skill when working on anything related to wiit.cloud — repos, team structure, GitLab, or cross-team context.

## Identity

- User: `pschmitt` / `philipp.schmitt@wiit.cloud`
- Teams: **EDGE** and **CKS** (Kubernetes)

## Repositories

- GitLab: `https://git.wiit.one`
- Local root: `~/devel/work/` (subdirs by team — see below)
- Repo inventory: `~/.config/mani/work.yaml`

## Skills

For issue tracking, use the `jira` skill (`jira.wiit.one`).
For documentation, use the `confluence` skill (`wiki.wiit.one`).
For on-call / alerts, use `opsgenie::alerts` (zsh) or query `https://api.eu.opsgenie.com/v2/` directly with the team API key from `zhj rbw::get -f "opsgenie api key (<team>)" "Atlassian (WIIT)"`. Teams: `edge-stack`, `gksv3-on-call`, `gksv3-support-schedule`.

## Teams

See `references/conventions.md` for per-team GitLab groups, local paths, Jira boards, Confluence spaces, and OpsGenie details.
