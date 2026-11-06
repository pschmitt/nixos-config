---
name: do-stuff
description: Work through the user's idea backlog in the Todoist project "🤓 Nerdery". Use when the user says "do stuff", "what should we work on", "pick something from my ideas/backlog/nerdery", or tells you about an idea, side project or "would be nice if" that should be captured as a Todoist task.
---

# do-stuff

The Todoist project **🤓 Nerdery** (id `6gfWcx5q832xJ6XJ`) is where the user keeps ideas and side projects for homelab, Home Assistant, skills and their own tools. This skill has two jobs: pick something from it and start on it, and capture new ideas into it.

Use the Todoist MCP (`mcp__plugin_hm_todoist__*`). Sections: `🖲️ Homelab` (`6gfWfg7J77gPhfhJ`), `🍱 Home Assistant` (`6gfWfg2XqxvRf9cJ`), `Later ™️` (`6ggpWgPW6wXx7WXr`, the parking lot). Tasks outside any section are fresh, unsorted ideas.

## Capture an idea

Whenever the user mentions an idea, a "we should", a "would be nice", or a thing to look at later, create a task in the Nerdery project without asking, then confirm in one line.

- Title: one leading emoji that fits the topic, then a short imperative or noun phrase, matching the existing tasks.
- Put the section that fits (Homelab, Home Assistant); leave it unsectioned when unclear. Do not use `Later` unless the user says so.
- Put context the user gave in the description. Add the `ha` or `homelab` label when it applies (check existing labels with `find-labels`).
- Search first (`find-tasks` with `searchText`) so you extend an existing task rather than duplicate it.
- Capturing is not a request to start the work. Capture, then carry on with what you were doing.

## Pick something to work on

1. `find-tasks` with `projectId` `6gfWcx5q832xJ6XJ` (and `find-completed-tasks` only if you need history). Read descriptions and comments (`find-comments`) for earlier notes.
2. Triage each open task into a rough size. Ground this in the repo and the infrastructure, not the title alone: check whether the thing is already done, half done, or blocked.
   - **Quick win**: under about 30 minutes, one repo, clear outcome, safe to verify.
   - **Medium**: a focused session, some design or a deploy.
   - **Big or unclear**: needs a decision from the user, hardware, or a design first.
   - **Stale**: already done, obsolete or superseded. Propose closing it, never complete it silently.
3. Propose, do not just start: give a short ranked list (3 to 5 items) with size, why now, and a recommendation. Prefer quick wins that unblock other things, items with a due date, and ideas that have momentum (recent notes, open branches). Skip items needing physical action unless the user asks.
4. Wait for the user's pick, then do the work under the normal repository rules (`AGENTS.md`, Concord `start_work`, `rworker` for builds, commit, push and deploy when verified).

## Keep the tasks current

- Write findings back to the task as you learn them: a short note in the description (or a comment with `add-comments` for dated progress) covering what you found, the chosen approach, blockers, and links to commits, branches or PRs. Never put secret values or private hostnames' credentials there.
- When the user confirms the work is done and deployed, complete the task (`complete-tasks`). If it stalls, record why and move it to `Later` only when the user agrees.
- Split a task that turns out to be bigger than it looked into subtasks instead of overloading one description.
- Breadcrumbs matter more than polish: a future session should be able to resume from the task alone.
