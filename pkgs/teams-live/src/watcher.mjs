import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  STATUS_REACTIONS,
  STATUS_BY_REACTION,
  COMMAND_REACTIONS,
  BOT_WATERMARK,
  botSentMessageIds,
  recordBotMessageId,
  addReaction,
  removeReaction,
  sendReply,
  sendDirectMessage,
  updateReply,
  getThreadMessages,
  getCalendarView,
  escapeHtml,
} from './teams.mjs';

const log = (...args) => console.error(new Date().toISOString(), '[watcher]', ...args);

const HEADSUP_PREFIX = 'headsup: ';
const CI_PREFIX = 'CI pipeline ';
const REBASE_PREFIX = '**Rebase';

const HELP_TEXT =
  '🤖 **teams-live slash commands**:\n\n' +
  '- `/approve [link]`: Approves the target MR (requires passing CI & no rebase needed).\n' +
  '- `/rebase [link]`: Triggers a GitLab rebase for the target MR (if conflict-free).\n' +
  '- `/status [link]`: Checks CI, approvals, and rebase state for the target MR.\n' +
  '- `/mrs`: Lists open, non-draft merge requests in the group.\n' +
  '- `/sprint`: Summary of active sprint tasks (To Do, In Progress, In Review).\n' +
  '- `/meetings`: Summary of meetings for the rest of the current week.\n' +
  '- `/weather [location]`: Shows current weather for location (default: Berlin).\n' +
  '- `/random`: Outputs a random fact.\n' +
  '- `/marco`: Diagnostic round-trip latency and echo probe.\n' +
  '- `/kick <nick> [reason]`: Ejects a user from the channel.\n' +
  '- `/ban <nick>`: Bans a user from the channel.\n' +
  '- `/exec <cmd>`: Executes a command.\n' +
  '- `/help` (or `/usage`): Lists supported slash commands.\n\n' +
  '_Target an MR by replying to its message or sending the command immediately after._';

const KNOWN_COMMANDS = [
  '/approve',
  '/rebase',
  '/status',
  '/mrs',
  '/sprint',
  '/meetings',
  '/weather',
  '/random',
  '/marco',
  '/kick',
  '/ban',
  '/exec',
  '/help',
  '/usage',
];

function levenshteinDistance(a, b) {
  const m = a.length;
  const n = b.length;
  const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost
      );
    }
  }
  return dp[m][n];
}

function toMockingCase(str) {
  return str
    .split('')
    .map((c, i) => (i % 2 === 0 ? c.toLowerCase() : c.toUpperCase()))
    .join('');
}

function getMrStatusEmoji(detailedStatus) {
  switch (detailedStatus) {
    case 'mergeable':
      return '✅';
    case 'not_approved':
      return '👀';
    case 'need_rebase':
      return '⚠️';
    case 'ci_still_running':
      return '⏳';
    case 'ci_must_pass':
      return '❌';
    case 'conflict':
      return '💥';
    case 'checking':
      return '🔄';
    case 'draft_status':
      return '📝';
    default:
      return '🔹';
  }
}

function isBotMr(mr) {
  const username = (mr.author?.username || '').toLowerCase();
  const name = (mr.author?.name || '').toLowerCase();
  const title = (mr.title || '').toLowerCase();
  return (
    Boolean(mr.author?.bot) ||
    username.includes('renovate') ||
    username.includes('bot') ||
    name.includes('renovate') ||
    name.includes('bot') ||
    title.startsWith('chore(deps') ||
    title.startsWith('update dependency') ||
    title.startsWith('update module') ||
    title.startsWith('pin dependency') ||
    title.startsWith('lock file maintenance')
  );
}

export class MergeRequestWatcher {
  constructor({ config, gitlab, jira, authManager }) {
    this.config = config;
    this.gitlab = gitlab;
    this.jira = jira;
    this.authManager = authManager;
    this.pollIntervalMs = (config.gitlab.poll_interval_seconds || 60) * 1000;
    this.historyLimit = config.gitlab.history_limit || 50;
    this.historyMaxAgeMinutes = config.gitlab?.history_max_age_minutes ?? 10;
    this.maxWatchDurationMs = (config.gitlab?.max_watch_duration_seconds ?? 7200) * 1000;

    this.watchedConversations = new Set();
    this.conversationMeta = new Map();
    for (const c of config.conversations) {
      this.watchedConversations.add(c.id);
      this.conversationMeta.set(c.id, c);
      try {
        const decoded = decodeURIComponent(c.id);
        this.watchedConversations.add(decoded);
        this.conversationMeta.set(decoded, c);
      } catch {}
    }

    this.watched = new Map();
    this.pollTimer = null;
    this.precomputeTimer = null;
    this.selfMri = null;

    this.cacheTtlMs = 15 * 60 * 1000; // 15 minutes
    this.precomputeIntervalMs = 10 * 60 * 1000; // 10 minutes
    this.mrsCache = { text: null, timestamp: 0, loading: null };
    this.sprintCache = { text: null, timestamp: 0, loading: null };
    this.meetingsCache = { text: null, timestamp: 0, loading: null };

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

  getAdminConversationId() {
    const notesConv = this.config.conversations.find(
      (c) => c.id === '48:notes' || (c.name && c.name.toLowerCase().includes('notes'))
    );
    return notesConv ? notesConv.id : '48:notes';
  }

  async sendStartupAnnouncement() {
    const adminConv = this.getAdminConversationId();
    if (!adminConv) return;

    const hostname = os.hostname();
    const pid = process.pid;
    const version = process.version;
    const platform = `${process.platform} ${process.arch}`;
    const startTime = new Date().toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
    const convNames = this.config.conversations.map((c) => c.name || c.id).join(', ');
    const memRss = Math.round(process.memoryUsage().rss / 1024 / 1024);

    const msg =
      '🚀 **teams-live started**\n\n' +
      `- **Host**: \`${hostname}\`\n` +
      `- **PID**: \`${pid}\`\n` +
      `- **Runtime**: Node.js \`${version}\` (${platform})\n` +
      `- **Memory**: ${memRss} MB\n` +
      `- **Started**: ${startTime}\n` +
      `- **Watched Conversations**: ${this.watchedConversations.size} (${convNames})\n` +
      `- **GitLab**: Polling every ${this.pollIntervalMs / 1000}s\n` +
      `- **Jira**: ${this.jira?.isConfigured() ? 'Active (CKS)' : 'Not configured'}\n` +
      `- **Precompute Cache**: Active (every ${this.precomputeIntervalMs / 60000}m)`;

    log(`Sending startup announcement to ${adminConv}...`);
    await sendDirectMessage(adminConv, msg);
  }

  async sendShutdownAnnouncement(signal = 'SIGTERM') {
    const adminConv = this.getAdminConversationId();
    if (!adminConv) return;

    const hostname = os.hostname();
    const pid = process.pid;
    const uptimeSec = Math.floor(process.uptime());
    const hours = Math.floor(uptimeSec / 3600);
    const minutes = Math.floor((uptimeSec % 3600) / 60);
    const seconds = uptimeSec % 60;
    const uptimeStr = `${hours > 0 ? `${hours}h ` : ''}${minutes}m ${seconds}s`;
    const shutdownTime = new Date().toISOString().replace('T', ' ').slice(0, 19) + ' UTC';

    const msg =
      '🛑 **teams-live shutting down**\n\n' +
      `- **Host**: \`${hostname}\`\n` +
      `- **PID**: \`${pid}\`\n` +
      `- **Signal**: \`${signal}\`\n` +
      `- **Uptime**: ${uptimeStr}\n` +
      `- **Time**: ${shutdownTime}`;

    log(`Sending shutdown announcement (${signal}) to ${adminConv}...`);
    await sendDirectMessage(adminConv, msg);
  }

  setSelfMri(mri) {
    this.selfMri = mri;
  }

  isOwnMessage(fromMri, text, messageId = null, clientMessageId = null, rawHtml = null) {
    if (messageId && botSentMessageIds.has(String(messageId))) return true;
    if (clientMessageId && botSentMessageIds.has(String(clientMessageId))) return true;

    const t = text || '';
    if (t.includes(BOT_WATERMARK)) return true;
    if (rawHtml && rawHtml.includes(BOT_WATERMARK)) return true;

    if (
      t.startsWith(HEADSUP_PREFIX) ||
      t.includes(CI_PREFIX) ||
      t.includes(REBASE_PREFIX) ||
      t.includes('Approved ') ||
      t.includes('Cannot approve') ||
      t.includes('already approved') ||
      t.includes('teams-live slash commands') ||
      t.includes('teams-live status') ||
      t.includes('POLO!') ||
      t.includes('was kicked from the conversation') ||
      t.includes('was banned from the conversation') ||
      t.includes('Random Fact') ||
      t.includes('📊') ||
      t.includes('Open Merge Requests') ||
      t.includes('No open merge requests found') ||
      t.includes('Current Sprint Tasks') ||
      t.includes('No active sprint tasks found') ||
      t.includes('Meetings for the rest of the week') ||
      t.includes('No upcoming meetings scheduled') ||
      t.includes('command not found') ||
      t.includes('[exec]') ||
      t.includes('dId yOu MeAn') ||
      t.includes('Rebase initiated') ||
      t.includes('Cannot automatically rebase') ||
      t.includes('Rebase required') ||
      t.includes('is now up to date') ||
      t.includes('Unknown command') ||
      t.includes('No merge request found') ||
      t.includes('Status check failed') ||
      t.includes('Weather lookup failed') ||
      t.includes('🌤️') ||
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

  async setCommandReaction(conversationId, messageId, reactionKey) {
    try {
      if (reactionKey !== COMMAND_REACTIONS.pending) {
        await removeReaction(conversationId, messageId, COMMAND_REACTIONS.pending).catch(() => {});
      }
      return await addReaction(conversationId, messageId, reactionKey);
    } catch (err) {
      log(`Failed to set reaction ${reactionKey} on ${messageId} in ${conversationId}: ${err.message}`);
    }
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
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.warning);
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
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `❌ Cannot approve [${mrRef}](${mrUrl}): no CI pipeline found.`
          );
          continue;
        }

        if (pipe.status === 'running' || pipe.status === 'pending') {
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.running);
          await sendReply(
            event.conversationId,
            event,
            `⏳ Cannot approve [${mrRef}](${mrUrl}): CI pipeline [#${pipe.id}](${pipe.web_url}) is still ${pipe.status}.`
          );
          continue;
        }

        if (pipe.status !== 'success') {
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `❌ Cannot approve [${mrRef}](${mrUrl}): CI pipeline [#${pipe.id}](${pipe.web_url}) is ${pipe.status}.`
          );
          continue;
        }

        // Precondition 3: Already approved?
        if (mrState.status === 'approved') {
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
          await sendReply(
            event.conversationId,
            event,
            `ℹ️ [${mrRef}](${mrUrl}) is already approved.`
          );
          continue;
        }

        // Precondition 4: Already merged or closed?
        if (mrState.status === 'merged' || mrState.status === 'closed') {
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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

        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
        await sendReply(
          event.conversationId,
          event,
          `✅ Approved [${mrRef}](${mrUrl})`
        );

        // Trigger immediate status check of watched entries so reactions update
        this.checkAllWatched().catch((err) => log(`Post-approval check failed: ${err.message}`));
      } catch (err) {
        log(`Error approving ${mr.project}!${mr.iid}: ${err.message}`);
        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `ℹ️ [${mrRef}](${mrUrl}) is already ${mrState.status}.`
          );
          continue;
        }

        if (mrState.details?.hasConflicts) {
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
          await sendReply(
            event.conversationId,
            event,
            `❌ Cannot automatically rebase [${mrRef}](${mrUrl}): branch has merge conflicts that must be resolved manually.`
          );
          continue;
        }

        if (!mrState.details?.needsRebase) {
          await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
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

        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.running);
        await sendReply(
          event.conversationId,
          event,
          `⏳ Rebase initiated for [${mrRef}](${mrUrl}). The watcher will update once complete.`
        );

        this.checkAllWatched().catch((err) => log(`Post-rebase check failed: ${err.message}`));
      } catch (err) {
        log(`Error rebasing ${mr.project}!${mr.iid}: ${err.message}`);
        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
        await sendReply(
          event.conversationId,
          event,
          `❌ Rebase failed for [${mrRef}](${mrUrl}): ${err.message}`
        );
      }
    }
  }

  async executeStatusCommand(event, args) {
    const hasDirectLinks = args.some((a) => this.gitlab.findMrLinks(a).length > 0);
    const hasQuoteLinks = this.gitlab.findMrLinks(event.rawHtml || '').length > 0;

    if (!hasDirectLinks && !hasQuoteLinks && args.length === 0) {
      log(`Executing bot runtime /status in ${event.conversationId}...`);
      const uptimeSec = Math.floor(process.uptime());
      const hours = Math.floor(uptimeSec / 3600);
      const minutes = Math.floor((uptimeSec % 3600) / 60);
      const seconds = uptimeSec % 60;
      const uptimeStr = `${hours > 0 ? `${hours}h ` : ''}${minutes}m ${seconds}s`;
      const memRss = Math.round(process.memoryUsage().rss / 1024 / 1024);
      const startTime = new Date(Date.now() - uptimeSec * 1000).toISOString().replace('T', ' ').slice(0, 19) + ' UTC';

      const convCount = this.watchedConversations.size;
      const watchedMrsCount = this.watched.size;
      const completedCount = this.completedMessages.size;
      const mrsAge = this.mrsCache.text ? `${Math.round((Date.now() - this.mrsCache.timestamp) / 1000)}s ago` : 'empty';
      const sprintAge = this.sprintCache.text ? `${Math.round((Date.now() - this.sprintCache.timestamp) / 1000)}s ago` : 'empty';
      const meetingsAge = this.meetingsCache.text ? `${Math.round((Date.now() - this.meetingsCache.timestamp) / 1000)}s ago` : 'empty';

      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
      await sendReply(
        event.conversationId,
        event,
        '🤖 **teams-live status**:\n\n' +
        `- **Uptime**: ${uptimeStr} (started ${startTime})\n` +
        `- **Runtime**: Node.js ${process.version} (PID ${process.pid})\n` +
        `- **Memory (RSS)**: ${memRss} MB\n` +
        `- **Trouter**: Connected 🟢\n` +
        `- **Watched Conversations**: ${convCount}\n` +
        `- **Active MR Watchers**: ${watchedMrsCount}\n` +
        `- **Precompute Cache**: /mrs (${mrsAge}), /sprint (${sprintAge}), /meetings (${meetingsAge})\n` +
        `- **Completed Message Cache**: ${completedCount}\n\n` +
        '_Tip: To check an MR status, use `/status [link]` or quote an MR message._'
      );
      return;
    }

    const mrs = await this.findTargetMrsForCommand(event, args);
    if (mrs.length === 0) {
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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

        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
        await sendReply(event.conversationId, event, `📊 [${mrRef}](${mrUrl})\n\n${statusText}`);
      } catch (err) {
        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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
      await this.setCommandReaction(event.conversationId, event.messageId, 'like');
      await sendReply(event.conversationId, event, `🌤️ ${weatherText}`);
    } catch (err) {
      log(`Weather lookup failed: ${err.message}`);
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
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
      await this.setCommandReaction(event.conversationId, event.messageId, 'like');
      await sendReply(event.conversationId, event, `💡 **Random Fact**:\n\n${data.text}`);
    } catch (err) {
      log(`Random fact failed: ${err.message}`);
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(event.conversationId, event, `❌ Failed to fetch a random fact: ${err.message}`);
    }
  }

  async getOrFetchMrsText({ force = false } = {}) {
    const now = Date.now();
    if (!force && this.mrsCache.text && now - this.mrsCache.timestamp < this.cacheTtlMs) {
      return this.mrsCache.text;
    }
    if (this.mrsCache.loading) {
      return await this.mrsCache.loading;
    }

    this.mrsCache.loading = (async () => {
      try {
        const mrs = await this.gitlab.getGroupMrs();
        let text;
        if (mrs.length === 0) {
          text = '📋 No open merge requests found.';
        } else {
          const groupPrefix = this.config.gitlab?.group
            ? new RegExp(`^${this.config.gitlab.group}/?`)
            : null;

          const formatMrLine = (mr) => {
            const fullRef = mr.references?.full || mr.references?.relative || `!${mr.iid}`;
            const displayRef = groupPrefix ? fullRef.replace(groupPrefix, '') : fullRef;
            const author = mr.author?.username || mr.author?.name || 'unknown';
            const statusEmoji = getMrStatusEmoji(mr.detailed_merge_status);
            return `- ${statusEmoji} [${displayRef}](${mr.web_url}): ${mr.title} (@${author})`;
          };

          const humanMrs = [];
          const botMrs = [];
          for (const mr of mrs) {
            if (isBotMr(mr)) {
              botMrs.push(mr);
            } else {
              humanMrs.push(mr);
            }
          }

          const sections = [];
          if (humanMrs.length > 0) {
            sections.push(`👤 **Human Merge Requests** (${humanMrs.length}):\n\n${humanMrs.map(formatMrLine).join('\n')}`);
          }
          if (botMrs.length > 0) {
            sections.push(`🤖 **Renovate / Bot Updates** (${botMrs.length}):\n\n${botMrs.map(formatMrLine).join('\n')}`);
          }

          text = `📋 **Open Merge Requests** (${mrs.length} total: ${humanMrs.length} human, ${botMrs.length} bot):\n\n${sections.join('\n\n')}`;
        }
        this.mrsCache.text = text;
        this.mrsCache.timestamp = Date.now();
        return text;
      } catch (err) {
        if (this.mrsCache.text) {
          log(`Failed to refresh /mrs cache (${err.message}), serving stale cache`);
          return this.mrsCache.text;
        }
        throw err;
      } finally {
        this.mrsCache.loading = null;
      }
    })();

    return await this.mrsCache.loading;
  }

  async executeCachedCommand(event, { name, getOrFetch, errorLabel }) {
    log(`Executing /${name} in ${event.conversationId}...`);
    try {
      const cacheObj = this[`${name}Cache`];
      const cached = cacheObj?.text;
      if (cached) {
        // 1. Output the cached message immediately
        const replyRes = await sendReply(event.conversationId, event, cached);
        await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);

        // 2. Start a fresh background fetch and update the message if it differs
        (async () => {
          try {
            const freshText = await getOrFetch({ force: true });
            if (freshText && freshText !== cached && replyRes?.ok && replyRes.value) {
              const serverMsgId = replyRes.value.timestamp || replyRes.value.messageId;
              log(`Updating /${name} reply (msg ${serverMsgId}) in ${event.conversationId} with fresh data`);
              await updateReply(event.conversationId, serverMsgId, event, freshText);
            }
          } catch (err) {
            log(`Background refresh for /${name} failed: ${err.message}`);
          }
        })();
        return;
      }

      // No cache yet: fetch synchronously
      const freshText = await getOrFetch({ force: true });
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
      await sendReply(event.conversationId, event, freshText);
    } catch (err) {
      log(`${errorLabel} failed: ${err.message}`);
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(
        event.conversationId,
        event,
        `❌ Failed to fetch ${errorLabel.toLowerCase()}: ${err.message}`
      );
    }
  }

  async executeMrsCommand(event) {
    await this.executeCachedCommand(event, {
      name: 'mrs',
      getOrFetch: (opts) => this.getOrFetchMrsText(opts),
      errorLabel: 'Group MRs lookup',
    });
  }

  async getOrFetchSprintText({ force = false } = {}) {
    if (!this.jira?.isConfigured()) {
      return '❌ Jira integration is not configured.';
    }
    const now = Date.now();
    if (!force && this.sprintCache.text && now - this.sprintCache.timestamp < this.cacheTtlMs) {
      return this.sprintCache.text;
    }
    if (this.sprintCache.loading) {
      return await this.sprintCache.loading;
    }

    this.sprintCache.loading = (async () => {
      try {
        const { total, inProgress, inReview, todo } = await this.jira.getActiveSprintTasks();
        if (total === 0) {
          const text = '🏃 No active sprint tasks found.';
          this.sprintCache.text = text;
          this.sprintCache.timestamp = Date.now();
          return text;
        }

        const sections = [];
        if (inProgress.length > 0) {
          const lines = [`**In Progress** (${inProgress.length}):`];
          for (const t of inProgress) {
            const keyRef = t.url ? `[${t.key}](${t.url})` : `**${t.key}**`;
            lines.push(`- ${keyRef}: ${t.summary} (@${t.assignee})`);
          }
          sections.push(lines.join('\n'));
        }

        if (inReview.length > 0) {
          const lines = [`**In Review** (${inReview.length}):`];
          for (const t of inReview) {
            const keyRef = t.url ? `[${t.key}](${t.url})` : `**${t.key}**`;
            lines.push(`- ${keyRef}: ${t.summary} (@${t.assignee})`);
          }
          sections.push(lines.join('\n'));
        }

        if (todo.length > 0) {
          const lines = [`**To Do** (${todo.length}):`];
          for (const t of todo) {
            const keyRef = t.url ? `[${t.key}](${t.url})` : `**${t.key}**`;
            lines.push(`- ${keyRef}: ${t.summary} (@${t.assignee})`);
          }
          sections.push(lines.join('\n'));
        }

        const text = `🏃 **Current Sprint Tasks** (${total} active):\n\n${sections.join('\n\n')}`;
        this.sprintCache.text = text;
        this.sprintCache.timestamp = Date.now();
        return text;
      } catch (err) {
        if (this.sprintCache.text) {
          log(`Failed to refresh /sprint cache (${err.message}), serving stale cache`);
          return this.sprintCache.text;
        }
        throw err;
      } finally {
        this.sprintCache.loading = null;
      }
    })();

    return await this.sprintCache.loading;
  }

  async executeSprintCommand(event) {
    if (!this.jira?.isConfigured()) {
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(
        event.conversationId,
        event,
        '❌ Jira integration is not configured.'
      );
      return;
    }

    await this.executeCachedCommand(event, {
      name: 'sprint',
      getOrFetch: (opts) => this.getOrFetchSprintText(opts),
      errorLabel: 'Sprint tasks lookup',
    });
  }

  async getOrFetchMeetingsText({ force = false } = {}) {
    const now = Date.now();
    if (!force && this.meetingsCache.text && now - this.meetingsCache.timestamp < this.cacheTtlMs) {
      return this.meetingsCache.text;
    }
    if (this.meetingsCache.loading) {
      return await this.meetingsCache.loading;
    }

    this.meetingsCache.loading = (async () => {
      try {
        const nowDate = new Date();
        const endOfWeek = new Date(nowDate);
        const day = endOfWeek.getDay();
        const diffToSunday = (7 - day) % 7;
        endOfWeek.setDate(endOfWeek.getDate() + diffToSunday);
        endOfWeek.setHours(23, 59, 59, 999);

        let res = await getCalendarView({
          startDate: nowDate.toISOString(),
          endDate: endOfWeek.toISOString(),
          limit: 50,
        });

        if (!res.ok) {
          throw new Error(res.error?.message || 'Calendar view request failed');
        }

        let meetings = (res.value?.meetings || []).filter(
          (m) => m.myResponse !== 'Declined'
        );

        let isNextWeek = false;
        if (meetings.length === 0) {
          // No more meetings for the rest of this week -> fetch next week's meetings
          const nextWeekStart = new Date(endOfWeek.getTime() + 1); // Next Monday 00:00:00.000
          const nextWeekEnd = new Date(nextWeekStart);
          nextWeekEnd.setDate(nextWeekEnd.getDate() + 6);
          nextWeekEnd.setHours(23, 59, 59, 999);

          const nextRes = await getCalendarView({
            startDate: nextWeekStart.toISOString(),
            endDate: nextWeekEnd.toISOString(),
            limit: 50,
          });

          if (nextRes.ok) {
            meetings = (nextRes.value?.meetings || []).filter((m) => m.myResponse !== 'Declined');
            isNextWeek = true;
          }
        }

        let text;
        if (meetings.length === 0) {
          text = '📅 No upcoming meetings scheduled for this week or next week.';
        } else {
          meetings.sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());

          const byDate = new Map();
          for (const m of meetings) {
            const start = new Date(m.startTime);
            const dateKey = start.toLocaleDateString('en-GB', {
              weekday: 'long',
              month: 'short',
              day: 'numeric',
              timeZone: 'Europe/Berlin',
            });
            if (!byDate.has(dateKey)) {
              byDate.set(dateKey, []);
            }
            byDate.get(dateKey).push(m);
          }

          const sections = [];
          for (const [dateStr, dayMeetings] of byDate.entries()) {
            const lines = [`**${dateStr}**:`];
            for (const m of dayMeetings) {
              const startStr = new Date(m.startTime).toLocaleTimeString('en-GB', {
                hour: '2-digit',
                minute: '2-digit',
                timeZone: 'Europe/Berlin',
              });
              const endStr = new Date(m.endTime).toLocaleTimeString('en-GB', {
                hour: '2-digit',
                minute: '2-digit',
                timeZone: 'Europe/Berlin',
              });
              const organizer = m.organizer?.name ? ` _(${m.organizer.name})_` : '';
              const link = m.joinUrl || (m.threadId ? `https://teams.microsoft.com/l/chat/${encodeURIComponent(m.threadId)}/0` : null);
              const subjectRef = link ? `[${m.subject}](${link})` : `**${m.subject}**`;
              lines.push(`- ${startStr} - ${endStr}: ${subjectRef}${organizer}`);
            }
            sections.push(lines.join('\n'));
          }

          const header = isNextWeek
            ? '📅 **Meetings for next week** (none remaining this week)'
            : '📅 **Meetings for the rest of the week**';

          text = `${header} (${meetings.length}):\n\n${sections.join('\n\n')}`;
        }

        this.meetingsCache.text = text;
        this.meetingsCache.timestamp = Date.now();
        return text;
      } catch (err) {
        if (this.meetingsCache.text) {
          log(`Failed to refresh /meetings cache (${err.message}), serving stale cache`);
          return this.meetingsCache.text;
        }
        throw err;
      } finally {
        this.meetingsCache.loading = null;
      }
    })();

    return await this.meetingsCache.loading;
  }

  async executeMeetingsCommand(event) {
    await this.executeCachedCommand(event, {
      name: 'meetings',
      getOrFetch: (opts) => this.getOrFetchMeetingsText(opts),
      errorLabel: 'Calendar meetings lookup',
    });
  }

  async executeExecCommand(event, args) {
    const cmd = args.join(' ').trim();
    const trollUser = this.config.teams?.troll_user;
    const senderMri = event.fromMri || '';
    const isTroll = trollUser && (senderMri === trollUser || senderMri.endsWith(trollUser.split(':').pop()));

    log(`Executing /exec from ${event.from || senderMri} (troll=${Boolean(isTroll)}) in ${event.conversationId}: ${cmd}`);

    if (isTroll) {
      const emojis = ['🤡', '🥑', '👾', '🚀', '🍄', '🦖', '🦥', '🌯', '🎪', '🍕', '🧨', '👻', '🦄', '🍹', '🎲', '🧶'];
      const shuffled = [...emojis].sort(() => 0.5 - Math.random());
      const selected = shuffled.slice(0, 3).join(' ');
      await this.setCommandReaction(event.conversationId, event.messageId, 'like');
      await sendReply(event.conversationId, event, `${selected}: command not found`);
      return;
    }

    await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
    if (!cmd) {
      await sendReply(event.conversationId, event, '`$ `\n\n```\n[exec] No command specified\n```');
    } else {
      await sendReply(
        event.conversationId,
        event,
        `\`$ ${escapeHtml(cmd)}\`\n\n\`\`\`\n[exec] Process finished with exit code 0\n\`\`\``
      );
    }
  }

  async executeBanCommand(event, args) {
    const target = args.join(' ').trim() || event.from || 'User';
    log(`Executing /ban for ${target} in ${event.conversationId}...`);
    await this.setCommandReaction(event.conversationId, event.messageId, 'like');
    await sendReply(
      event.conversationId,
      event,
      `🔨 *${target} was banned from the conversation.*`
    );
  }

  async executeKickCommand(event, args = []) {
    const target = args.join(' ').trim() || event.from || 'User';
    log(`Executing /kick for ${target} in ${event.conversationId}...`);
    await this.setCommandReaction(event.conversationId, event.messageId, 'like');
    await sendReply(
      event.conversationId,
      event,
      `👢 *${target} was kicked from the conversation.*`
    );
  }

  async executeMarcoCommand(event) {
    const sender = event.from || 'friend';
    log(`Executing /marco from ${sender} in ${event.conversationId}...`);
    await this.setCommandReaction(event.conversationId, event.messageId, 'like');
    await sendReply(event.conversationId, event, `🏊 **POLO!**`);
  }

  async executeHelpCommand(event) {
    log(`Executing /help in ${event.conversationId}...`);
    await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);
    await sendReply(event.conversationId, event, HELP_TEXT);
  }

  async handleSlashCommand(event) {
    const parsed = this.parseSlashCommand(event.content);
    if (!parsed) return;

    const { command, args } = parsed;
    log(`Handling slash command ${command} from ${event.from || event.fromMri} in ${event.conversationId}`);

    // React immediately with eyes emoji to acknowledge command receipt
    await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.pending);

    if (command === '/approve') {
      await this.executeApproveCommand(event, args);
    } else if (command === '/rebase') {
      await this.executeRebaseCommand(event, args);
    } else if (command === '/status') {
      await this.executeStatusCommand(event, args);
    } else if (command === '/mrs') {
      await this.executeMrsCommand(event);
    } else if (command === '/sprint') {
      await this.executeSprintCommand(event);
    } else if (command === '/meetings') {
      await this.executeMeetingsCommand(event);
    } else if (command === '/weather') {
      await this.executeWeatherCommand(event, args);
    } else if (command === '/random') {
      await this.executeRandomCommand(event);
    } else if (command === '/marco') {
      await this.executeMarcoCommand(event);
    } else if (command === '/kick') {
      await this.executeKickCommand(event, args);
    } else if (command === '/ban') {
      await this.executeBanCommand(event, args);
    } else if (command === '/exec') {
      await this.executeExecCommand(event, args);
    } else if (command === '/help' || command === '/usage') {
      await this.executeHelpCommand(event);
    } else {
      let bestMatch = null;
      let minDistance = Infinity;

      for (const known of KNOWN_COMMANDS) {
        if (known === '/usage') continue;
        const dist = levenshteinDistance(command, known);
        if (dist < minDistance) {
          minDistance = dist;
          bestMatch = known;
        }
      }

      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.warning);
      if (bestMatch && minDistance <= 3) {
        await sendReply(
          event.conversationId,
          event,
          `🤔 ${toMockingCase('did you mean')} ${bestMatch}?`
        );
      } else {
        await sendReply(
          event.conversationId,
          event,
          `Unknown command \`${command}\`. Use \`/help\` to see available commands.`
        );
      }
    }
  }

  async handleIncomingEvent(event) {
    if (event.kind !== 'NewMessage') return;
    const convId = event.conversationId;
    let decodedConvId = convId;
    try {
      decodedConvId = decodeURIComponent(convId);
    } catch {}

    if (!this.watchedConversations.has(convId) && !this.watchedConversations.has(decodedConvId)) return;

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

    if (this.isOwnMessage(event.fromMri, event.content, event.messageId, event.clientMessageId, event.rawHtml)) return;

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
    const processedHistoryCommands = new Set();

    for (const conversationId of this.watchedConversations) {
      log(
        `Scanning recent history of ${conversationId} (limit ${this.historyLimit}, max age ${this.historyMaxAgeMinutes}m)...`
      );
      let result = await getThreadMessages(conversationId, {
        limit: this.historyLimit,
        startTime: cutoffTime,
      });
      if (!result.ok) {
        log(`History scan of ${conversationId} failed (${result.error?.message}), retrying in 2s...`);
        await new Promise((r) => setTimeout(r, 2000));
        result = await getThreadMessages(conversationId, {
          limit: this.historyLimit,
          startTime: cutoffTime,
        });
      }
      if (!result.ok) {
        log(`History scan retry of ${conversationId} failed: ${result.error?.message}`);
        continue;
      }

      for (const msg of result.value.messages) {
        if (this.completedMessages.has(String(msg.id))) continue;
        if (botSentMessageIds.has(String(msg.id))) continue;

        const msgTime = msg.composeTime ? new Date(msg.composeTime).getTime() : Number(msg.id) || 0;
        if (msgTime && msgTime < cutoffTime) continue;

        const senderMri = msg.sender?.mri?.split('/contacts/').pop();
        if (this.isOwnMessage(senderMri, msg.content, msg.id, msg.clientMessageId, msg.content)) continue;

        // Check if message is an unhandled slash command from recent history
        if (this.isSlashCommand(msg.content)) {
          const parsed = this.parseSlashCommand(msg.content);
          if (parsed) {
            const dedupKey = `${conversationId}:${parsed.command}:${parsed.args.join(' ')}`.toLowerCase();
            if (processedHistoryCommands.has(dedupKey)) {
              log(`Skipping duplicate slash command from history: "${msg.content}" in ${conversationId}`);
              continue;
            }
            processedHistoryCommands.add(dedupKey);
          }

          const hasOwnReaction = (msg.reactions ?? []).some((r) => r.user?.mri === self);
          if (!hasOwnReaction) {
            log(
              `Processing missed slash command from history: "${msg.content}" from ${msg.sender?.displayName || senderMri} in ${conversationId}`
            );
            this.handleSlashCommand({
              kind: 'NewMessage',
              conversationId,
              messageId: msg.id,
              clientMessageId: msg.clientMessageId,
              content: msg.content,
              from: msg.sender?.displayName,
              fromMri: senderMri,
              links: (msg.links ?? []).map((l) => l.url),
            }).catch((err) => log(`Error executing missed slash command from history: ${err.message}`));
          }
          continue;
        }

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

  scheduleNextPrecompute() {
    if (this.precomputeTimer) {
      clearTimeout(this.precomputeTimer);
      this.precomputeTimer = null;
    }
    // Base 10 minutes with +/- 2 minutes jitter (8 to 12 minutes)
    const jitterMs = Math.floor((Math.random() * 4 - 2) * 60 * 1000);
    const delay = Math.max(60 * 1000, this.precomputeIntervalMs + jitterMs);
    log(`Scheduling next precompute in ${(delay / 1000 / 60).toFixed(1)}m (jitter: ${(jitterMs / 1000).toFixed(0)}s)`);
    this.precomputeTimer = setTimeout(async () => {
      await this.runPrecompute();
      this.scheduleNextPrecompute();
    }, delay);
    if (this.precomputeTimer.unref) this.precomputeTimer.unref();
  }

  async runPrecompute() {
    log('Precomputing /mrs, /sprint, and /meetings cache in background...');
    await Promise.allSettled([
      this.getOrFetchMrsText({ force: true }).catch((err) => log(`Precompute /mrs failed: ${err.message}`)),
      this.getOrFetchSprintText({ force: true }).catch((err) => log(`Precompute /sprint failed: ${err.message}`)),
      this.getOrFetchMeetingsText({ force: true }).catch((err) => log(`Precompute /meetings failed: ${err.message}`)),
    ]);
    log('Precompute /mrs, /sprint, and /meetings cache completed');
  }

  startPrecompute() {
    // Initial run after brief delay with jitter (5 to 15 seconds)
    const initialDelay = 5_000 + Math.floor(Math.random() * 10_000);
    if (this.precomputeTimer) clearTimeout(this.precomputeTimer);
    this.precomputeTimer = setTimeout(async () => {
      await this.runPrecompute();
      this.scheduleNextPrecompute();
    }, initialDelay);
    if (this.precomputeTimer.unref) this.precomputeTimer.unref();
  }

  startPolling() {
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.pollTimer = setInterval(() => {
      this.checkAllWatched().catch((err) => log(`Polling check failed: ${err.message}`));
    }, this.pollIntervalMs);

    if (this.pollTimer.unref) this.pollTimer.unref();
    this.startPrecompute();
  }

  stop() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    if (this.precomputeTimer) {
      clearTimeout(this.precomputeTimer);
      this.precomputeTimer = null;
    }
  }
}
