import {
  STATUS_REACTIONS,
  STATUS_BY_REACTION,
  addReaction,
  removeReaction,
  sendReply,
  updateReply,
  getThreadMessages,
} from './teams.mjs';

const log = (...args) => console.error(new Date().toISOString(), '[watcher]', ...args);

const HEADSUP_PREFIX = 'headsup: ';
const CI_PREFIX = 'CI pipeline ';
const REBASE_PREFIX = '**Rebase';

export class MergeRequestWatcher {
  constructor({ config, gitlab, authManager }) {
    this.config = config;
    this.gitlab = gitlab;
    this.authManager = authManager;
    this.pollIntervalMs = (config.gitlab.poll_interval_seconds || 60) * 1000;
    this.historyLimit = config.gitlab.history_limit || 50;

    this.watchedConversations = new Set(config.conversations.map((c) => c.id));
    this.conversationMeta = new Map(config.conversations.map((c) => [c.id, c]));

    this.watched = new Map();
    this.pollTimer = null;
    this.selfMri = null;
  }

  setSelfMri(mri) {
    this.selfMri = mri;
  }

  isOwnMessage(fromMri, text) {
    if (this.selfMri && fromMri === this.selfMri) {
      const t = text || '';
      if (t.startsWith(HEADSUP_PREFIX) || t.includes(CI_PREFIX) || t.includes(REBASE_PREFIX)) {
        return true;
      }
    }
    return false;
  }

  watch(conversationId, messageId, text, { from = '', fromMri = '', initialStatus = null } = {}) {
    const mrLinks = this.gitlab.findMrLinks(text);
    if (mrLinks.length === 0) return;

    const mrsMap = new Map();
    const initialMrStatus = initialStatus === 'approved' ? 'approved' : null;
    for (const mr of mrLinks) {
      const key = `${mr.project}!${mr.iid}`;
      if (!mrsMap.has(key)) {
        mrsMap.set(key, {
          project: mr.project,
          iid: mr.iid,
          status: initialMrStatus,
          ciMessageServerId: null,
          lastReportedPipelineId: null,
          lastReportedPipelineStatus: null,
          rebaseMessageServerId: null,
          lastReportedNeedsRebase: null,
        });
      }
    }

    const key = `${conversationId}/${messageId}`;
    this.watched.set(key, {
      conversationId,
      messageId,
      from,
      fromMri,
      content: text,
      mrs: [...mrsMap.values()],
      status: initialStatus,
    });

    log(`watching MRs in ${conversationId}/${messageId}: ${[...mrsMap.keys()].join(', ')}`);
    this.checkWatchedKey(key).catch((err) => log(`initial check failed for ${key}: ${err.message}`));
  }

  async setReactionStatus(entry, newStatus) {
    const { conversationId, messageId } = entry;
    if (newStatus && newStatus !== entry.status) {
      const result = await addReaction(conversationId, messageId, STATUS_REACTIONS[newStatus]);
      if (!result.ok) log(`adding ${newStatus} reaction failed: ${result.error?.message}`);
    }

    if (entry.status && entry.status !== newStatus) {
      const result = await removeReaction(conversationId, messageId, STATUS_REACTIONS[entry.status]);
      if (!result.ok) log(`removing ${entry.status} reaction failed: ${result.error?.message}`);
    }

    entry.status = newStatus;
  }

  async sendHeadsup(entry, mr) {
    if (!this.config.gitlab.notify_approval_lost) return;
    const mrUrl = this.gitlab.mrLink(mr.project, mr.iid);
    const msg = `${HEADSUP_PREFIX}${mrUrl} needs a new approval`;
    log(`posting heads-up for ${mr.project}!${mr.iid} to ${entry.conversationId}`);
    const result = await sendReply(entry.conversationId, entry, msg);
    if (!result.ok) {
      log(`heads-up reply failed: ${result.error?.message}`);
    }
  }

  async handleCiStatusComment(entry, mr, pipeline, mrDetails) {
    if (!this.config.gitlab.notify_ci) return;

    let icon = 'ℹ️';
    let statusText = pipeline.status;
    let shouldNotify = false;

    if (pipeline.status === 'success') {
      icon = '✅';
      statusText = 'passed';
      shouldNotify = this.config.gitlab.notify_ci_on_success;
    } else if (pipeline.status === 'failed') {
      icon = '❌';
      statusText = 'failed';
      shouldNotify = this.config.gitlab.notify_ci_on_failure;
    } else if (pipeline.status === 'running') {
      icon = '⏳';
      statusText = 'running';
      shouldNotify = true;
    } else if (pipeline.status === 'canceled') {
      icon = '⚠️';
      statusText = 'canceled';
      shouldNotify = true;
    }

    if (!shouldNotify) return;

    const mrRef = `!${mr.iid} (${mr.project})`;
    const mrUrl = mrDetails?.web_url || this.gitlab.mrLink(mr.project, mr.iid);
    const pipeUrl = pipeline.web_url;
    const msg = `${icon} ${CI_PREFIX}**${statusText}** for [${mrRef}](${mrUrl})\n\n[Pipeline #${pipeline.id}](${pipeUrl})`;

    if (mr.ciMessageServerId) {
      log(`updating CI status comment (${pipeline.status}) for ${mr.project}!${mr.iid} (msg ${mr.ciMessageServerId})`);
      const updateResult = await updateReply(entry.conversationId, mr.ciMessageServerId, entry, msg);
      if (updateResult.ok) return;
      log(`updating CI comment failed (${updateResult.error?.message}), falling back to new reply`);
    }

    log(`posting new CI status comment (${pipeline.status}) for ${mr.project}!${mr.iid}`);
    const result = await sendReply(entry.conversationId, entry, msg);
    if (result.ok && result.value?.timestamp) {
      mr.ciMessageServerId = String(result.value.timestamp);
    } else if (!result.ok) {
      log(`CI status reply failed: ${result.error?.message}`);
    }
  }

  async handleRebaseComment(entry, mr, mrDetails) {
    if (!this.config.gitlab.notify_rebase) return;

    const mrRef = `!${mr.iid} (${mr.project})`;
    const mrUrl = mrDetails?.web_url || this.gitlab.mrLink(mr.project, mr.iid);

    if (mrDetails.needsRebase) {
      if (mr.lastReportedNeedsRebase === true) return; // already reported

      const reason = mrDetails.hasConflicts ? 'merge conflicts' : 'behind target branch';
      const msg = `⚠️ **Rebase required** for [${mrRef}](${mrUrl})\n\nBranch has ${reason} (status: \`${mrDetails.detailedMergeStatus}\`).`;

      if (mr.rebaseMessageServerId) {
        log(`updating rebase comment for ${mr.project}!${mr.iid} (msg ${mr.rebaseMessageServerId})`);
        const updateResult = await updateReply(entry.conversationId, mr.rebaseMessageServerId, entry, msg);
        if (updateResult.ok) {
          mr.lastReportedNeedsRebase = true;
          return;
        }
        log(`updating rebase comment failed (${updateResult.error?.message}), falling back to new reply`);
      }

      log(`posting rebase required comment for ${mr.project}!${mr.iid}`);
      const result = await sendReply(entry.conversationId, entry, msg);
      if (result.ok && result.value?.timestamp) {
        mr.rebaseMessageServerId = String(result.value.timestamp);
      } else if (!result.ok) {
        log(`rebase reply failed: ${result.error?.message}`);
      }
      mr.lastReportedNeedsRebase = true;
    } else if (mr.lastReportedNeedsRebase === true) {
      // Was previously reported needing rebase, now up to date! Update the comment in-place.
      const msg = `✅ **Rebased** [${mrRef}](${mrUrl}) is now up to date and conflict-free.`;
      if (mr.rebaseMessageServerId) {
        log(`updating rebase comment to resolved for ${mr.project}!${mr.iid} (msg ${mr.rebaseMessageServerId})`);
        const updateResult = await updateReply(entry.conversationId, mr.rebaseMessageServerId, entry, msg);
        if (!updateResult.ok) {
          log(`updating rebase comment to resolved failed: ${updateResult.error?.message}`);
        }
      }
      mr.lastReportedNeedsRebase = false;
    }
  }

  async checkWatchedKey(key) {
    const entry = this.watched.get(key);
    if (!entry) return;

    try {
      const statuses = [];
      for (const mr of entry.mrs) {
        const mrState = await this.gitlab.getMrStatus(mr.project, mr.iid);
        statuses.push(mrState.status);

        // Heads-up: was approved, but now pending
        if (mr.status === 'approved' && mrState.status === 'pending') {
          await this.sendHeadsup(entry, mr);
        }

        // CI Pipeline status check (with in-place update)
        if (mrState.pipeline) {
          const pipe = mrState.pipeline;
          if (mr.lastReportedPipelineId !== pipe.id || mr.lastReportedPipelineStatus !== pipe.status) {
            await this.handleCiStatusComment(entry, mr, pipe, mrState);
            mr.lastReportedPipelineId = pipe.id;
            mr.lastReportedPipelineStatus = pipe.status;
          }
        }

        // Rebase status check (with in-place update)
        await this.handleRebaseComment(entry, mr, mrState);

        mr.status = mrState.status;
      }

      // Overall status:
      let overallStatus = null;
      if (statuses.includes('pending')) {
        overallStatus = 'pending';
      } else if (statuses.includes('approved')) {
        overallStatus = 'approved';
      } else if (statuses.every((s) => s === 'merged')) {
        overallStatus = 'merged';
      }

      if (overallStatus !== entry.status) {
        await this.setReactionStatus(entry, overallStatus);
        log(`${key} status updated -> ${overallStatus ?? 'closed'}`);
      }

      if (statuses.every((s) => s === 'merged' || s === 'closed')) {
        log(`All MRs merged/closed for ${key}, unwatching`);
        this.watched.delete(key);
      }
    } catch (err) {
      log(`Error checking MRs for ${key}: ${err.message}`);
    }
  }

  async checkAllWatched() {
    for (const key of this.watched.keys()) {
      await this.checkWatchedKey(key);
    }
  }

  handleIncomingEvent(event) {
    if (event.kind !== 'NewMessage') return;
    if (!this.watchedConversations.has(event.conversationId)) return;
    if (this.isOwnMessage(event.fromMri, event.content)) return;

    const fullText = [event.content, ...(event.links ?? [])].filter(Boolean).join(' ');
    this.watch(event.conversationId, event.messageId, fullText, {
      from: event.from,
      fromMri: event.fromMri,
    });
  }

  async watchHistory() {
    const auth = await this.authManager.ensureValidAuth();
    const self = auth.userMri;
    this.setSelfMri(self);

    for (const conversationId of this.watchedConversations) {
      log(`Scanning recent history of ${conversationId} (limit ${this.historyLimit})...`);
      const result = await getThreadMessages(conversationId, { limit: this.historyLimit });
      if (!result.ok) {
        log(`History scan of ${conversationId} failed: ${result.error?.message}`);
        continue;
      }

      for (const msg of result.value.messages) {
        const senderMri = msg.sender?.mri?.split('/contacts/').pop();
        if (this.isOwnMessage(senderMri, msg.content)) continue;

        const ownReactions = (msg.reactions ?? [])
          .filter((r) => r.user?.mri === self)
          .map((r) => STATUS_BY_REACTION.get(r.key))
          .filter(Boolean);

        if (ownReactions.includes('merged')) continue;

        const currentStatus = ownReactions.find(Boolean) ?? null;
        const text = [msg.content, ...(msg.links ?? []).map((l) => l.url)].filter(Boolean).join(' ');

        this.watch(conversationId, msg.id, text, {
          from: msg.sender?.displayName || '',
          fromMri: senderMri || '',
          initialStatus: currentStatus,
        });
      }
    }
  }

  startPolling() {
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.pollTimer = setInterval(() => {
      this.checkAllWatched().catch((err) => log(`Polling check failed: ${err.message}`));
    }, this.pollIntervalMs);

    if (this.pollTimer.unref) this.pollTimer.unref();
  }

  stop() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }
}
