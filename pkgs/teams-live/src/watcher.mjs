import fs from 'node:fs';
import path from 'node:path';
import {
  STATUS_REACTIONS,
  STATUS_BY_REACTION,
  COMMAND_REACTIONS,
  botSentMessageIds,
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
    this.historyMaxAgeMinutes = config.gitlab?.history_max_age_minutes ?? 10;
    this.maxWatchDurationMs = (config.gitlab?.max_watch_duration_seconds ?? 7200) * 1000;

    this.watchedConversations = new Set(config.conversations.map((c) => c.id));
    this.conversationMeta = new Map(config.conversations.map((c) => [c.id, c]));

    this.watched = new Map();
    this.pollTimer = null;
    this.selfMri = null;

    const stateDir = process.env.XDG_STATE_HOME || path.join(process.cwd(), 'state');
    if (!fs.existsSync(stateDir)) {
      try {
        fs.mkdirSync(stateDir, { recursive: true });
      } catch {
        // ignore
      }
    }
    this.stateFile = path.join(stateDir, 'watcher-state.json');
    this.completedMessages = new Set();
    this.savedEntries = new Map();
    this.loadState();
  }

  loadState() {
    try {
      if (fs.existsSync(this.stateFile)) {
        const raw = fs.readFileSync(this.stateFile, 'utf8');
        const data = JSON.parse(raw);
        if (Array.isArray(data.completedMessages)) {
          this.completedMessages = new Set(data.completedMessages);
        }
        if (Array.isArray(data.botMessageIds)) {
          for (const id of data.botMessageIds) {
            recordBotMessageId(id);
          }
        }
        if (data.entries && typeof data.entries === 'object') {
          this.savedEntries = new Map(Object.entries(data.entries));
        }
        log(
          `Loaded state from ${this.stateFile}: ${this.completedMessages.size} completed messages, ${this.savedEntries.size} saved active entries`
        );
      }
    } catch (err) {
      log(`Error loading state from ${this.stateFile}: ${err.message}`);
    }
  }

  saveState() {
    try {
      const entriesObj = {};
      for (const [k, v] of this.watched.entries()) {
        entriesObj[k] = {
          status: v.status,
          createdAt: v.createdAt,
          mrs: v.mrs.map((m) => ({
            project: m.project,
            iid: m.iid,
            status: m.status,
            ciMessageServerId: m.ciMessageServerId,
            lastReportedPipelineId: m.lastReportedPipelineId,
            lastReportedPipelineStatus: m.lastReportedPipelineStatus,
            rebaseMessageServerId: m.rebaseMessageServerId,
            lastReportedNeedsRebase: m.lastReportedNeedsRebase,
          })),
        };
      }
      const completedArray = Array.from(this.completedMessages);
      const cappedCompleted = completedArray.length > 1000 ? completedArray.slice(-1000) : completedArray;
      const botArray = Array.from(botSentMessageIds);
      const cappedBot = botArray.length > 2000 ? botArray.slice(-2000) : botArray;

      const data = {
        completedMessages: cappedCompleted,
        botMessageIds: cappedBot,
        entries: entriesObj,
      };
      const tmpPath = `${this.stateFile}.tmp`;
      fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf8');
      fs.renameSync(tmpPath, this.stateFile);
    } catch (err) {
      log(`Error saving state to ${this.stateFile}: ${err.message}`);
    }
  }

  setSelfMri(mri) {
    this.selfMri = mri;
  }

  isOwnMessage(fromMri, text, messageId = null, clientMessageId = null) {
    if (messageId && botSentMessageIds.has(String(messageId))) return true;
    if (clientMessageId && botSentMessageIds.has(String(clientMessageId))) return true;

    const t = text || '';
    if (
      t.startsWith(HEADSUP_PREFIX) ||
      t.includes(CI_PREFIX) ||
      t.includes(REBASE_PREFIX) ||
      t.includes('Approved [!') ||
      t.includes('Cannot approve [!') ||
      t.includes('already approved') ||
      t.includes('teams-live slash commands') ||
      t.includes('POLO!') ||
      t.includes('was kicked from the conversation') ||
      t.includes('Random Fact') ||
      t.includes('📊 [!') ||
      t.includes('Rebase initiated') ||
      t.includes('Cannot automatically rebase') ||
      t.includes('Unknown command') ||
      t.includes('itemtype="http://schema.skype.com/Reply"')
    ) {
      return true;
    }

    return false;
  }

  watch(conversationId, messageId, text, { from = '', fromMri = '', initialStatus = null, isHistory = false } = {}) {
    const mrLinks = this.gitlab.findMrLinks(text);
    if (mrLinks.length === 0) return;

    const key = `${conversationId}/${messageId}`;
    const saved = this.savedEntries.get(key);

    const mrsMap = new Map();
    const initialMrStatus = initialStatus === 'approved' ? 'approved' : null;
    for (const mr of mrLinks) {
      const mrKey = `${mr.project}!${mr.iid}`;
      if (!mrsMap.has(mrKey)) {
        const savedMr = saved?.mrs?.find((m) => m.project === mr.project && String(m.iid) === String(mr.iid));
        mrsMap.set(mrKey, {
          project: mr.project,
          iid: mr.iid,
          status: savedMr?.status ?? initialMrStatus,
          ciMessageServerId: savedMr?.ciMessageServerId ?? null,
          lastReportedPipelineId: savedMr?.lastReportedPipelineId ?? null,
          lastReportedPipelineStatus: savedMr?.lastReportedPipelineStatus ?? null,
          rebaseMessageServerId: savedMr?.rebaseMessageServerId ?? null,
          lastReportedNeedsRebase: savedMr?.lastReportedNeedsRebase ?? null,
        });
      }
    }

    this.watched.set(key, {
      conversationId,
      messageId,
      from,
      fromMri,
      content: text,
      mrs: [...mrsMap.values()],
      status: saved?.status ?? initialStatus,
      isHistory,
      createdAt: saved?.createdAt ?? Date.now(),
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
    if (!this.config.gitlab.notify?.approval_lost) return;
    const mrUrl = this.gitlab.mrLink(mr.project, mr.iid);
    const msg = `${HEADSUP_PREFIX}${mrUrl} needs a new approval`;
    log(`posting heads-up for ${mr.project}!${mr.iid} to ${entry.conversationId}`);
    const result = await sendReply(entry.conversationId, entry, msg);
    if (!result.ok) {
      log(`heads-up reply failed: ${result.error?.message}`);
    }
  }

  async handleCiStatusComment(entry, mr, pipeline, mrDetails) {
    if (!this.config.gitlab.notify?.ci?.enable) return;

    let icon = 'ℹ️';
    let statusText = pipeline.status;
    let shouldNotify = false;

    if (pipeline.status === 'success') {
      icon = '✅';
      statusText = 'passed';
      shouldNotify = this.config.gitlab.notify?.ci?.on_success;
    } else if (pipeline.status === 'failed') {
      icon = '❌';
      statusText = 'failed';
      shouldNotify = this.config.gitlab.notify?.ci?.on_failure;
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
      this.saveState();
    } else if (!result.ok) {
      log(`CI status reply failed: ${result.error?.message}`);
    }
  }

  async handleRebaseComment(entry, mr, mrDetails) {
    if (!this.config.gitlab.notify?.rebase) return;

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
        this.saveState();
      } else if (!result.ok) {
        log(`rebase reply failed: ${result.error?.message}`);
      }
      mr.lastReportedNeedsRebase = true;
      this.saveState();
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

    if (Date.now() - (entry.createdAt || 0) > this.maxWatchDurationMs) {
      log(`Watch duration for ${key} exceeded ${this.maxWatchDurationMs / 1000}s, unwatching`);
      this.completedMessages.add(String(entry.messageId));
      this.watched.delete(key);
      this.saveState();
      return;
    }

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
            if (!entry.isHistory || mr.lastReportedPipelineStatus !== null) {
              await this.handleCiStatusComment(entry, mr, pipe, mrState);
            }
            mr.lastReportedPipelineId = pipe.id;
            mr.lastReportedPipelineStatus = pipe.status;
          }
        }

        // Rebase status check (with in-place update)
        if (!entry.isHistory || mr.lastReportedNeedsRebase !== null) {
          await this.handleRebaseComment(entry, mr, mrState);
        } else if (mrState.details) {
          mr.lastReportedNeedsRebase = mrState.details.needsRebase;
        }

        mr.status = mrState.status;
      }

      entry.isHistory = false;

      // Overall status:
      let overallStatus = null;
      const anyCiFailed = entry.mrs.some(
        (m) => m.lastReportedPipelineStatus === 'failed' && m.status !== 'merged' && m.status !== 'closed'
      );

      if (statuses.every((s) => s === 'merged')) {
        overallStatus = 'merged';
      } else if (anyCiFailed) {
        overallStatus = 'failed';
      } else if (statuses.includes('approved')) {
        overallStatus = 'approved';
      } else if (statuses.includes('pending')) {
        overallStatus = 'pending';
      }

      if (overallStatus !== entry.status) {
        await this.setReactionStatus(entry, overallStatus);
        log(`${key} status updated -> ${overallStatus ?? 'closed'}`);
      }

      if (statuses.every((s) => s === 'merged' || s === 'closed')) {
        log(`All MRs merged/closed for ${key}, unwatching`);
        this.completedMessages.add(String(entry.messageId));
        this.watched.delete(key);
        this.saveState();
      } else {
        this.saveState();
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

  isSlashCommand(text) {
    if (!text) return false;
    const trimmed = text.trim();
    return trimmed.startsWith('/') && !trimmed.startsWith('//');
  }

  parseSlashCommand(text) {
    if (!text) return null;
    const trimmed = text.trim();
    if (!trimmed.startsWith('/')) return null;

    const parts = trimmed.split(/\s+/);
    const command = parts[0].toLowerCase();
    const args = parts.slice(1);
    return { command, args, fullText: trimmed };
  }

  async findTargetMrsForCommand(event, args) {
    // 1. Direct MR links in the command arguments (e.g. "/approve https://..."):
    const directText = args.join(' ');
    const directLinks = this.gitlab.findMrLinks(directText);
    if (directLinks.length > 0) return directLinks;

    // 2. Direct MR links in the command message itself (or HTML quote block):
    const htmlLinks = this.gitlab.findMrLinks(event.rawHtml || '');
    if (htmlLinks.length > 0) return htmlLinks;

    // 3. Fallback: Search conversation history for the most recent message with an MR link
    try {
      const thread = await getThreadMessages(event.conversationId, { limit: 15 });
      if (thread.ok && Array.isArray(thread.value?.messages)) {
        const msgs = [...thread.value.messages].sort((a, b) => Number(b.id || 0) - Number(a.id || 0));
        for (const msg of msgs) {
          if (String(msg.id) === String(event.messageId)) continue;
          const msgText = [msg.content, ...(msg.links ?? []).map((l) => l.url)].filter(Boolean).join(' ');
          const links = this.gitlab.findMrLinks(msgText);
          if (links.length > 0) {
            log(`Found target MR in preceding message ${msg.id}: ${links.map((l) => `${l.project}!${l.iid}`).join(', ')}`);
            return links;
          }
        }
      }
    } catch (err) {
      log(`Error looking up recent messages for slash command: ${err.message}`);
    }

    return [];
  }

  async executeApproveCommand(event, args) {
    log(`Executing /approve command from ${event.from || event.fromMri} in ${event.conversationId}...`);
    const mrs = await this.findTargetMrsForCommand(event, args);
    if (mrs.length === 0) {
      await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(
        event.conversationId,
        event,
        '❌ No merge request found to approve. Quote a message containing an MR or send `/approve` immediately following it.'
      );
      return;
    }

    for (const mr of mrs) {
      const mrRef = `!${mr.iid} (${mr.project})`;
      const mrUrl = this.gitlab.mrLink(mr.project, mr.iid);

      try {
        const mrState = await this.gitlab.getMrStatus(mr.project, mr.iid);

        // Precondition 1: Rebase check
        if (mrState.details?.needsRebase) {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.warning);
          const reason = mrState.details.hasConflicts ? 'merge conflicts' : 'needs to be rebased';
          await sendReply(
            event.conversationId,
            event,
            `⚠️ Cannot approve [${mrRef}](${mrUrl}): branch has ${reason} (\`${mrState.details.detailedMergeStatus}\`).`
          );
          continue;
        }

        // Precondition 2: CI check
        const pipe = mrState.pipeline;
        if (!pipe) {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `❌ Cannot approve [${mrRef}](${mrUrl}): no CI pipeline found.`
          );
          continue;
        }

        if (pipe.status === 'running' || pipe.status === 'pending') {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.running);
          await sendReply(
            event.conversationId,
            event,
            `⏳ Cannot approve [${mrRef}](${mrUrl}): CI pipeline [#${pipe.id}](${pipe.web_url}) is still ${pipe.status}.`
          );
          continue;
        }

        if (pipe.status !== 'success') {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `❌ Cannot approve [${mrRef}](${mrUrl}): CI pipeline [#${pipe.id}](${pipe.web_url}) is ${pipe.status}.`
          );
          continue;
        }

        // Precondition 3: Already approved?
        if (mrState.status === 'approved') {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
          await sendReply(
            event.conversationId,
            event,
            `ℹ️ [${mrRef}](${mrUrl}) is already approved.`
          );
          continue;
        }

        // Precondition 4: Already merged or closed?
        if (mrState.status === 'merged' || mrState.status === 'closed') {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `ℹ️ [${mrRef}](${mrUrl}) is already ${mrState.status}.`
          );
          continue;
        }

        // Action: Approve MR via GitLab API
        log(`Approving ${mr.project}!${mr.iid} via GitLab API...`);
        await this.gitlab.approveMr(mr.project, mr.iid);
        log(`Approved ${mr.project}!${mr.iid} successfully`);

        await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
        await sendReply(
          event.conversationId,
          event,
          `✅ Approved [${mrRef}](${mrUrl})`
        );

        // Trigger immediate status check of watched entries so reactions update
        this.checkAllWatched().catch((err) => log(`Post-approval check failed: ${err.message}`));
      } catch (err) {
        log(`Error approving ${mr.project}!${mr.iid}: ${err.message}`);
        await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
        await sendReply(
          event.conversationId,
          event,
          `❌ Approval failed for [${mrRef}](${mrUrl}): ${err.message}`
        );
      }
    }
  }

  async executeRebaseCommand(event, args) {
    log(`Executing /rebase command from ${event.from || event.fromMri} in ${event.conversationId}...`);
    const mrs = await this.findTargetMrsForCommand(event, args);
    if (mrs.length === 0) {
      await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(
        event.conversationId,
        event,
        '❌ No merge request found to rebase. Quote an MR message or send `/rebase` immediately following it.'
      );
      return;
    }

    for (const mr of mrs) {
      const mrRef = `!${mr.iid} (${mr.project})`;
      const mrUrl = this.gitlab.mrLink(mr.project, mr.iid);

      try {
        const mrState = await this.gitlab.getMrStatus(mr.project, mr.iid);

        if (mrState.status === 'merged' || mrState.status === 'closed') {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `ℹ️ [${mrRef}](${mrUrl}) is already ${mrState.status}.`
          );
          continue;
        }

        if (mrState.details?.hasConflicts) {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `❌ Cannot automatically rebase [${mrRef}](${mrUrl}): branch has merge conflicts that must be resolved manually.`
          );
          continue;
        }

        if (!mrState.details?.needsRebase) {
          await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
          await sendReply(
            event.conversationId,
            event,
            `ℹ️ [${mrRef}](${mrUrl}) is already up to date with target branch.`
          );
          continue;
        }

        log(`Triggering GitLab rebase for ${mr.project}!${mr.iid}...`);
        await this.gitlab.rebaseMr(mr.project, mr.iid);
        log(`Rebase triggered for ${mr.project}!${mr.iid}`);

        await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.running);
        await sendReply(
          event.conversationId,
          event,
          `⏳ Rebase initiated for [${mrRef}](${mrUrl}). The watcher will update once complete.`
        );

        this.checkAllWatched().catch((err) => log(`Post-rebase check failed: ${err.message}`));
      } catch (err) {
        log(`Error rebasing ${mr.project}!${mr.iid}: ${err.message}`);
        await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
        await sendReply(
          event.conversationId,
          event,
          `❌ Rebase failed for [${mrRef}](${mrUrl}): ${err.message}`
        );
      }
    }
  }

  async executeStatusCommand(event, args) {
    const mrs = await this.findTargetMrsForCommand(event, args);
    if (mrs.length === 0) {
      await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(
        event.conversationId,
        event,
        '❌ No merge request found. Quote an MR message or send `/status` immediately following it.'
      );
      return;
    }

    for (const mr of mrs) {
      const mrRef = `!${mr.iid} (${mr.project})`;
      const mrUrl = this.gitlab.mrLink(mr.project, mr.iid);
      try {
        const mrState = await this.gitlab.getMrStatus(mr.project, mr.iid);
        const pipe = mrState.pipeline;
        const pipeText = pipe ? `[#${pipe.id} (${pipe.status})](${pipe.web_url})` : 'none';
        const rebaseText = mrState.details?.needsRebase
          ? `⚠️ Needs rebase (${mrState.details.hasConflicts ? 'conflicts' : 'behind'})`
          : '✅ Up to date';
        const statusText = `Status: **${mrState.status}**\n\nPipeline: ${pipeText}\n\nBranch: ${rebaseText}`;

        await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
        await sendReply(event.conversationId, event, `📊 [${mrRef}](${mrUrl})\n\n${statusText}`);
      } catch (err) {
        await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
        await sendReply(event.conversationId, event, `❌ Status check failed for [${mrRef}](${mrUrl}): ${err.message}`);
      }
    }
  }

  async executeWeatherCommand(event, args) {
    const location = args.join(' ').trim() || 'Berlin';
    log(`Executing /weather for "${location}" in ${event.conversationId}...`);
    try {
      const url = `https://wttr.in/${encodeURIComponent(location)}?format=%l:+%c+%t+(feels+like+%f),+humidity:+%h,+wind:+%w`;
      const res = await fetch(url, {
        headers: { 'User-Agent': 'curl/8.0' },
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const weatherText = (await res.text()).trim();
      await addReaction(event.conversationId, event.messageId, 'like');
      await sendReply(event.conversationId, event, `🌤️ ${weatherText}`);
    } catch (err) {
      log(`Weather lookup failed: ${err.message}`);
      await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(event.conversationId, event, `❌ Weather lookup failed for "${location}": ${err.message}`);
    }
  }

  async executeRandomCommand(event) {
    log(`Executing /random fact in ${event.conversationId}...`);
    try {
      const res = await fetch('https://uselessfacts.jsph.pl/api/v2/facts/random', {
        headers: { 'User-Agent': 'teams-live/1.0', Accept: 'application/json' },
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      await addReaction(event.conversationId, event.messageId, 'like');
      await sendReply(event.conversationId, event, `💡 **Random Fact**:\n\n${data.text}`);
    } catch (err) {
      log(`Random fact failed: ${err.message}`);
      await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(event.conversationId, event, `❌ Failed to fetch a random fact: ${err.message}`);
    }
  }

  async executeMarcoCommand(event) {
    const sender = event.from || 'friend';
    log(`Executing /marco from ${sender} in ${event.conversationId}...`);
    await addReaction(event.conversationId, event.messageId, 'like');
    await sendReply(event.conversationId, event, `🏊 **POLO!**`);
  }

  async executeKickCommand(event) {
    const sender = event.from || 'User';
    log(`Executing /kick for ${sender} in ${event.conversationId}...`);
    await addReaction(event.conversationId, event.messageId, 'like');
    await sendReply(
      event.conversationId,
      event,
      `👢 *${sender} was kicked from the conversation.*`
    );
  }

  async executeHelpCommand(event) {
    log(`Executing /help in ${event.conversationId}...`);
    await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
    await sendReply(
      event.conversationId,
      event,
      '🤖 **teams-live slash commands**:\n\n' +
      '- `/approve [link]`: Approves the target MR (requires passing CI & no rebase needed).\n' +
      '- `/rebase [link]`: Triggers a GitLab rebase for the target MR (if conflict-free).\n' +
      '- `/status [link]`: Checks CI, approvals, and rebase state for the target MR.\n' +
      '- `/weather [location]`: Shows current weather for location (default: Berlin).\n' +
      '- `/random`: Outputs a random fact from uselessfacts.jsph.pl.\n' +
      '- `/marco`: Answers with "POLO!".\n' +
      '- `/kick`: Mentions the sender and pretends they were kicked.\n' +
      '- `/help`: Lists supported slash commands.\n\n' +
      '_Target an MR by replying to its message or sending the command immediately after._'
    );
  }

  async handleSlashCommand(event) {
    const parsed = this.parseSlashCommand(event.content);
    if (!parsed) return;

    const { command, args } = parsed;
    log(`Handling slash command ${command} from ${event.from || event.fromMri} in ${event.conversationId}`);

    if (command === '/approve') {
      await this.executeApproveCommand(event, args);
    } else if (command === '/rebase') {
      await this.executeRebaseCommand(event, args);
    } else if (command === '/status') {
      await this.executeStatusCommand(event, args);
    } else if (command === '/weather') {
      await this.executeWeatherCommand(event, args);
    } else if (command === '/random') {
      await this.executeRandomCommand(event);
    } else if (command === '/marco') {
      await this.executeMarcoCommand(event);
    } else if (command === '/kick') {
      await this.executeKickCommand(event);
    } else if (command === '/help') {
      await this.executeHelpCommand(event);
    } else {
      await addReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.warning);
      await sendReply(
        event.conversationId,
        event,
        `Unknown command \`${command}\`. Use \`/help\` to see available commands.`
      );
    }
  }

  async handleIncomingEvent(event) {
    if (event.kind !== 'NewMessage') return;
    if (!this.watchedConversations.has(event.conversationId)) return;

    // Ignore bot's own messages immediately to prevent self-trigger loops
    if (botSentMessageIds.has(String(event.messageId)) || botSentMessageIds.has(String(event.clientMessageId))) {
      return;
    }

    // Check for slash commands first (even from self)
    if (this.isSlashCommand(event.content)) {
      try {
        await this.handleSlashCommand(event);
      } catch (err) {
        log(`Error executing slash command: ${err.message}`);
      }
      return;
    }

    if (this.isOwnMessage(event.fromMri, event.content, event.messageId, event.clientMessageId)) return;

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

    const cutoffTime = Date.now() - this.historyMaxAgeMinutes * 60 * 1000;

    for (const conversationId of this.watchedConversations) {
      log(
        `Scanning recent history of ${conversationId} (limit ${this.historyLimit}, max age ${this.historyMaxAgeMinutes}m)...`
      );
      const result = await getThreadMessages(conversationId, {
        limit: this.historyLimit,
        startTime: cutoffTime,
      });
      if (!result.ok) {
        log(`History scan of ${conversationId} failed: ${result.error?.message}`);
        continue;
      }

      for (const msg of result.value.messages) {
        if (this.completedMessages.has(String(msg.id))) continue;
        if (botSentMessageIds.has(String(msg.id))) continue;

        const msgTime = msg.composeTime ? new Date(msg.composeTime).getTime() : Number(msg.id) || 0;
        if (msgTime && msgTime < cutoffTime) continue;

        const senderMri = msg.sender?.mri?.split('/contacts/').pop();
        if (this.isOwnMessage(senderMri, msg.content, msg.id)) continue;

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
          isHistory: true,
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
