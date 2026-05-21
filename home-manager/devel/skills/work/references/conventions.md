# Work Conventions

## EDGE team

### GitLab groups

| Group           | URL                                      |
|-----------------|------------------------------------------|
| `edge-stack`    | `https://git.wiit.one/edge-stack`        |
| `ooe`           | `https://git.wiit.one/ooe`               |
| `ooe/argocd`    | `https://git.wiit.one/ooe/argocd`        |

### Local paths

| Area                  | Path                                   |
|-----------------------|----------------------------------------|
| OOE / ArgoCD repos    | `~/devel/work/ooe/`                    |
| GitOps / ENOP-SRE     | `~/devel/work/gitops/`                 |
| Operations Center     | `~/devel/work/operations-center/`      |
| Misc (snek, sheriff…) | `~/devel/work/*.git`                   |

### Jira

- Project key: `EDGE`
- Kanban board: **966** — "EDGE board"
- See `jira` skill for API access and JQL patterns.

### Confluence

- Space: `edge`
- See `confluence` skill for API access and CQL patterns.

### OpsGenie

- API endpoint: `https://api.eu.opsgenie.com/v2/`
- API key: `zhj rbw::get -f "opsgenie api key (edge-stack)" "Atlassian (WIIT)"`
- Team: **EDGE-STACK** (`856b67ca-9880-4632-889a-0ab28d2a31a6`)
- Schedule: **Edge Stack Schedule** (`5b8e9d89-1562-4345-9441-703224afb255`)
- Escalation: **SRE-Ops_escalation** (`fc63c49d-26c7-4565-9fc8-826c63a28feb`)
- On-call tooling: `opsgenie::on-duty` (zsh), repo `git@git.wiit.one:edge-stack/opsgenie-sheriff.git`

---

## CKS team

### GitLab groups

| Group                    | URL                                                  |
|--------------------------|------------------------------------------------------|
| `kubernetes`             | `https://git.wiit.one/kubernetes`                    |
| `kubernetes/code`        | `https://git.wiit.one/kubernetes/code`               |
| `kubernetes/config`      | `https://git.wiit.one/kubernetes/config`             |
| `kubernetes/capi`        | `https://git.wiit.one/kubernetes/capi`               |
| `kubernetes/images`      | `https://git.wiit.one/kubernetes/images`             |
| `kubernetes/docs`        | `https://git.wiit.one/kubernetes/docs`               |

### Local paths

| Area              | Path                       |
|-------------------|----------------------------|
| All CKS repos     | `~/devel/work/cks/`        |

### Jira

- Project key: `CKS`
- Sprint board: **617** — "CKS Development" (scrum, sprint naming `CKS Sprint YYWW`)
- Helpdesk/kanban board: **1200** — "CKS HELPDESK"
- See `jira` skill for API access and JQL patterns.

### Confluence

- Space: `CKS`
- See `confluence` skill for API access and CQL patterns.

### OpsGenie

Note: the CKS team is named **GKSv3** in OpsGenie (legacy name).

- API endpoint: `https://api.eu.opsgenie.com/v2/`

**On-call (24/7)**
- API key: `zhj rbw::get -f "opsgenie api key (gksv3-on-call)" "Atlassian (WIIT)"`
- Team: **GKSv3 - On-Call** (`923da7a2-b1ab-4060-89ef-6a0394250379` — escalation)
- Schedule: **gksv3-on-call_schedule** (`8aa71a67-9ddd-4571-af97-06d1ddb3c7cb`)
- Escalation: **gksv3-on-call_escalation** (`923da7a2-b1ab-4060-89ef-6a0394250379`)

**Support (business hours)**
- API key: `zhj rbw::get -f "opsgenie api key (gksv3-support-schedule)" "Atlassian (WIIT)"`
- Team: **GKSv3 - Support schedule - Business Hours Only**
- Schedule: **gksv3-support_schedule** (`5a044893-0255-4246-8606-8e76949a861d`)
- Escalation: **gksv3-support_escalation** (`3cd62d69-3d53-4a54-ba8d-425d39893978`)
