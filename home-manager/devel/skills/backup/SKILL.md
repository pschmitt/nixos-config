---
name: backup
description: Create, locate, verify, or restore the user's ad-hoc backups of devices, services, configuration, or personal data under ~/Backups.
---

# Backups

The user's durable backup collection is `~/Backups`, organized mostly by device, service, or data source. Check for an existing matching directory before creating one; use a dated, descriptive name such as `<source>/YYYY-MM-DD-pre-<change>/`. Keep backups outside temporary and agent cache directories. For risky live service operations on hosts, follow the host-specific backup location in the relevant repository or operations skill as well.

- Establish what must be recoverable: configuration, custom scripts, credentials, service state and data, boot files, and separately mounted volumes as applicable. State omissions explicitly. For live databases use a consistent application-native backup or snapshot rather than assuming a file copy is consistent.
- Treat backups as sensitive. Create new backup directories with mode `700` and files with mode `600` when they may contain secrets; do not print archive contents or credentials. Preserve needed ownership, permissions, ACLs and extended attributes where practical.
- Verify successful capture and transfer: test archive readability, check expected important paths without exposing contents, and compare hashes or equivalent evidence. A checksum alone does not prove the capture is complete or restorable. Record the source, date, scope, exclusions and restoration details where useful; test restoration when appropriate.
- When restoring onto a fresh installation or a different architecture, reconcile file owners and groups by account name: numeric IDs can change between images. Check restored data as well as configuration, then verify service access and authentication, not just that units start.
- Never overwrite or delete existing backups casually. Report the backup path and verification, and distinguish backups from incomplete transfers or snapshots of a running system.
- `~/Backups` is a Syncthing folder; do not assume that synchronization has completed or that it provides an independent off-site copy. Check sync status when the task requires it.
