# teams-live

Real-time Microsoft Teams bot and watcher daemon integrated with GitLab, Jira, and OpsGenie.

## Features

- **Push Notifications & Trouter Integration**: Listens for live Teams events via Trouter websockets with automatic token refresh and self-healing authentication.
- **GitLab MR Tracking**: Monitors merge requests linked in watched chats, automatically reflects status via reactions (👀 pending review, 👍 approved, ❌ CI failure, ✅ merged), and posts/updates in-place comments for CI results, rebase requirements, and merges.
- **OpsGenie Integration**: Lists open alerts across CKS queues (On-Call & Support) sorted by priority with active on-duty personnel.
- **Jira Integration**: Displays active sprint task breakdowns (To Do, In Progress, In Review).
- **Calendar & Meetings**: Queries Microsoft Teams EMEA MiddleTier calendar for remaining weekly meetings with clickable Teams join links.
- **Slash Commands**:
  - `/mrs [all|bots]`: Group merge request overview with human MR priority.
  - `/alerts` (or `/opsgenie`) `[oncall|support]`: Live OpsGenie alerts and on-duty responders.
  - `/sprint`: Active Jira sprint tickets and assignees.
  - `/meetings`: Remaining weekly agenda with direct meeting links.
  - `/approve [link|all]`: Approves target GitLab MR (or `/approve all` for all eligible human MRs with green/no pipeline in the group).
  - `/rebase [link]`: Triggers conflict-free GitLab MR rebase.
  - `/status [link]`: Service runtime stats or target MR check.
  - `/leaderboard`: Tracks and ranks chat interactions and command usage.
  - `/weather [city]`: Current weather observations via wttr.in.
  - `/random`: Random trivia facts.
  - `/about`: Source repository and project information.

## Source & Development

- Repository: [nixos-config/pkgs/teams-live](https://github.com/pschmitt/nixos-config/tree/main/pkgs/teams-live)
- Author: [Philipp Schmitt](https://github.com/pschmitt)

## Support

If you find this useful, consider supporting further development:
👉 [Sponsor on GitHub](https://github.com/sponsors/pschmitt)
