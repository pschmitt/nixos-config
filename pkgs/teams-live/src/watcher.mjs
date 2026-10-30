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
import { formatOnDuty } from './opsgenie.mjs';

const log = (...args) => console.error(new Date().toISOString(), '[watcher]', ...args);

const HEADSUP_PREFIX = 'headsup: ';
const CI_PREFIX = 'CI pipeline ';
const REBASE_PREFIX = '**Rebase';

const HELP_TEXT =
  '🤖 **teams-live slash commands**:\n\n' +
  '- `/approve [link]`: Approves the target MR (requires passing CI & no rebase needed).\n' +
  '- `/rebase [link]`: Triggers a GitLab rebase for the target MR (if conflict-free).\n' +
  '- `/status [link]`: Checks CI, approvals, and rebase state for the target MR.\n' +
  '- `/mrs [all|bots]`: Lists open merge requests (human MRs + top 5 bot MRs; all shows all, bots shows only bots).\n' +
  '- `/alerts` (or `/opsgenie`) [oncall|support]: Open alerts in the CKS OpsGenie queues.\n' +
  '- `/sprint`: Summary of active sprint tasks (To Do, In Progress, In Review).\n' +
  '- `/meetings`: Summary of meetings for the rest of the current week.\n' +
  '- `/weather [location]`: Shows current weather for location (default: Berlin).\n' +
  '- `/random`: Outputs a random fact.\n' +
  '- `/marco`: Diagnostic round-trip latency and echo probe.\n' +
  '- `/leaderboard`: Shows top users by bot interactions and command usage.\n' +
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
  '/alerts',
  '/opsgenie',
  '/sprint',
  '/meetings',
  '/weather',
  '/random',
  '/marco',
  '/leaderboard',
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

function isReadyToMerge(mr) {
  if (mr.draft || mr.work_in_progress) return false;
  if (mr.detailed_merge_status === 'mergeable') return true;
  if (
    mr.merge_status === 'can_be_merged' &&
    mr.detailed_merge_status !== 'not_approved' &&
    mr.detailed_merge_status !== 'ci_must_pass' &&
    mr.detailed_merge_status !== 'ci_still_running' &&
    mr.detailed_merge_status !== 'need_rebase' &&
    mr.detailed_merge_status !== 'conflict'
  ) {
    return true;
  }
  return false;
}

function sortMrs(list) {
  return [...list].sort((a, b) => {
    const aReady = isReadyToMerge(a) ? 1 : 0;
    const bReady = isReadyToMerge(b) ? 1 : 0;
    if (aReady !== bReady) return bReady - aReady;
    const aTime = new Date(a.updated_at || 0).getTime();
    const bTime = new Date(b.updated_at || 0).getTime();
    return bTime - aTime;
  });
}

function getMrsMode(args = []) {
  const sub = (args[0] || '').toLowerCase().replace(/^-+/, '');
  if (sub === 'all' || sub === 'a') return 'all';
  if (
    sub === 'renovate' ||
    sub === 'renovates' ||
    sub === 'bots' ||
    sub === 'bot' ||
    sub === 'r' ||
    sub === 'b'
  ) {
    return 'bots';
  }
  return 'default';
}

const ALERT_PRIORITY_ORDER = { P1: 1, P2: 2, P3: 3, P4: 4, P5: 5 };

function sortAlerts(alerts) {
  return [...alerts].sort((a, b) => {
    const aPrio = ALERT_PRIORITY_ORDER[a.priority] || 99;
    const bPrio = ALERT_PRIORITY_ORDER[b.priority] || 99;
    if (aPrio !== bPrio) return aPrio - bPrio;

    const aTime = new Date(a.createdAt || a.lastOccurredAt || 0).getTime();
    const bTime = new Date(b.createdAt || b.lastOccurredAt || 0).getTime();
    return bTime - aTime;
  });
}

function getAlertPriorityBadge(priority) {
  switch (priority) {
    case 'P1':
      return '🚨 **P1**';
    case 'P2':
      return '🟠 **P2**';
    case 'P3':
      return '🟡 **P3**';
    case 'P4':
      return '🔵 **P4**';
    case 'P5':
      return '⚪ **P5**';
    default:
      return `🔹 **${priority || 'P?'}**`;
  }
}

function formatTimeAgo(dateStr) {
  if (!dateStr) return '';
  const diffMs = Date.now() - new Date(dateStr).getTime();
  if (diffMs < 0) return 'just now';
  const secs = Math.floor(diffMs / 1000);
  if (secs < 60) return `${secs}s ago`;
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function formatAlertLine(alert) {
  const pBadge = getAlertPriorityBadge(alert.priority);
  const linkRef = alert.tinyId ? `#${alert.tinyId}` : (alert.id ? alert.id.slice(0, 8) : 'alert');
  const link = `[${linkRef}](${alert.url})`;
  const ackBadge = alert.acknowledged ? ' `✔️ ACK\'ED`' : '';
  const snoozeBadge = alert.snoozed ? ' _(💤 snoozed)_' : '';
  const countStr = alert.count > 1 ? ` (🔄 ${alert.count}x)` : '';
  const timeStr = alert.createdAt ? ` — _${formatTimeAgo(alert.createdAt)}_` : '';
  return `- ${pBadge} ${link}: ${alert.message}${ackBadge}${snoozeBadge}${countStr}${timeStr}`;
}

function formatAlertsText(data, mode = 'all') {
  if (!data) return '❌ Failed to fetch OpsGenie alerts.';

  const {
    onCallAlerts = [],
    supportAlerts = [],
    onCallDuty = [],
    supportDuty = [],
    onCallError,
    supportError,
  } = data;
  const sortedOnCall = sortAlerts(onCallAlerts);
  const sortedSupport = sortAlerts(supportAlerts);
  const totalCount = sortedOnCall.length + sortedSupport.length;

  const onCallPerson = formatOnDuty(onCallDuty);
  const supportPerson = formatOnDuty(supportDuty);

  const showOnCall = mode === 'all' || mode === 'oncall';
  const showSupport = mode === 'all' || mode === 'support';

  if (totalCount === 0 && !onCallError && !supportError) {
    if (mode === 'oncall') {
      return `🎉 **CKS OpsGenie On-Call queue is clear!** (0 open alerts)\n\n👤 **On-Duty**: **${onCallPerson}**`;
    }
    if (mode === 'support') {
      return `🎉 **CKS OpsGenie Support queue is clear!** (0 open alerts)\n\n👤 **On-Duty**: **${supportPerson}**`;
    }
    return `🎉 **All CKS OpsGenie queues are clear!** (0 open alerts)\n\n👤 **On-Duty**: 📞 On-Call: **${onCallPerson}** · 💼 Support: **${supportPerson}**`;
  }

  const sections = [];

  if (showOnCall) {
    const dutyTag = ` (👤 **${onCallPerson}**)`;
    if (onCallError) {
      sections.push(`📞 **On-Call Queue**${dutyTag}:\n\n⚠️ *Failed to fetch on-call alerts: ${onCallError}*`);
    } else if (sortedOnCall.length === 0) {
      sections.push(`📞 **On-Call Queue**${dutyTag}: 🎉 _No open alerts_`);
    } else {
      const lines = sortedOnCall.map(formatAlertLine).join('\n');
      sections.push(`📞 **On-Call Queue**${dutyTag} (${sortedOnCall.length} open):\n\n${lines}`);
    }
  }

  if (showSupport) {
    const dutyTag = ` (👤 **${supportPerson}**)`;
    if (supportError) {
      sections.push(`💼 **Support Queue**${dutyTag}:\n\n⚠️ *Failed to fetch support alerts: ${supportError}*`);
    } else if (sortedSupport.length === 0) {
      sections.push(`💼 **Support Queue**${dutyTag}: 🎉 _No open alerts_`);
    } else {
      const lines = sortedSupport.map(formatAlertLine).join('\n');
      sections.push(`💼 **Support Queue**${dutyTag} (${sortedSupport.length} open):\n\n${lines}`);
    }
  }

  let title;
  if (mode === 'oncall') {
    title = `🚨 **CKS OpsGenie Alerts** (${sortedOnCall.length} on-call)\n👤 **On-Duty**: 📞 On-Call: **${onCallPerson}**`;
  } else if (mode === 'support') {
    title = `🚨 **CKS OpsGenie Alerts** (${sortedSupport.length} support)\n👤 **On-Duty**: 💼 Support: **${supportPerson}**`;
  } else {
    title = `🚨 **CKS OpsGenie Alerts** (${totalCount} open: ${sortedOnCall.length} on-call, ${sortedSupport.length} support)\n👤 **On-Duty**: 📞 On-Call: **${onCallPerson}** · 💼 Support: **${supportPerson}**`;
  }

  return `${title}\n\n${sections.join('\n\n')}`;
}

export class MergeRequestWatcher {
  constructor({ config, gitlab, jira, opsgenie, authManager }) {
    this.config = config;
    this.gitlab = gitlab;
    this.jira = jira;
    this.opsgenie = opsgenie;
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
    this.mrsCache = { data: null, timestamp: 0, loading: null };
    this.alertsCache = { data: null, timestamp: 0, loading: null };
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
    this.userInteractions = new Map();
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
        if (data.userInteractions && typeof data.userInteractions === 'object') {
          this.userInteractions = new Map(Object.entries(data.userInteractions));
        }
        log(
          `Loaded state from ${this.stateFile}: ${this.completedMessages.size} completed messages, ${this.savedEntries.size} saved active entries, ${this.userInteractions.size} tracked users`
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

      const interactionsObj = {};
      for (const [k, v] of this.userInteractions.entries()) {
        interactionsObj[k] = v;
      }

      const data = {
        completedMessages: cappedCompleted,
        botMessageIds: cappedBot,
        entries: entriesObj,
        userInteractions: interactionsObj,
      };
      const tmpPath = `${this.stateFile}.tmp`;
      fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf8');
      fs.renameSync(tmpPath, this.stateFile);
    } catch (err) {
      log(`Error saving state to ${this.stateFile}: ${err.message}`);
    }
  }

  recordUserInteraction(event, command) {
    const key = event.fromMri || event.from || 'unknown';
    const name = event.from || event.fromMri || 'Anonymous';
    let userStats = this.userInteractions.get(key);
    if (!userStats) {
      userStats = {
        name,
        mri: event.fromMri || '',
        count: 0,
        commands: {},
        lastSeen: Date.now(),
      };
      this.userInteractions.set(key, userStats);
    }
    if (event.from && userStats.name !== event.from) {
      userStats.name = event.from;
    }
    userStats.count = (userStats.count || 0) + 1;
    userStats.commands = userStats.commands || {};
    userStats.commands[command] = (userStats.commands[command] || 0) + 1;
    userStats.lastSeen = Date.now();
    this.saveState();
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
      t.includes('Renovate / Bot Updates') ||
      t.includes('No open renovate or bot merge requests found') ||
      t.includes('Bot Interaction Leaderboard') ||
      t.includes('CKS OpsGenie Alerts') ||
      t.includes('All CKS OpsGenie queues are clear!') ||
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

  async getOrFetchMrsData({ force = false } = {}) {
    const now = Date.now();
    if (!force && this.mrsCache.data && now - this.mrsCache.timestamp < this.cacheTtlMs) {
      return this.mrsCache.data;
    }
    if (this.mrsCache.loading) {
      return await this.mrsCache.loading;
    }

    this.mrsCache.loading = (async () => {
      try {
        const mrs = await this.gitlab.getGroupMrs();
        this.mrsCache.data = mrs;
        this.mrsCache.timestamp = Date.now();
        return mrs;
      } catch (err) {
        if (this.mrsCache.data) {
          log(`Failed to refresh /mrs cache (${err.message}), serving stale cache`);
          return this.mrsCache.data;
        }
        throw err;
      } finally {
        this.mrsCache.loading = null;
      }
    })();

    return await this.mrsCache.loading;
  }

  formatMrsText(mrs, mode = 'default') {
    if (!mrs || mrs.length === 0) {
      return '📋 No open merge requests found.';
    }

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

    const humanMrs = sortMrs(mrs.filter((mr) => !isBotMr(mr)));
    const botMrs = sortMrs(mrs.filter(isBotMr));

    if (mode === 'bots') {
      if (botMrs.length === 0) {
        return '🤖 No open renovate or bot merge requests found.';
      }
      return `🤖 **Renovate / Bot Updates** (${botMrs.length}):\n\n${botMrs.map(formatMrLine).join('\n')}`;
    }

    const sections = [];
    if (humanMrs.length > 0) {
      sections.push(`👤 **Human Merge Requests** (${humanMrs.length}):\n\n${humanMrs.map(formatMrLine).join('\n')}`);
    }

    if (botMrs.length > 0) {
      if (mode === 'all' || botMrs.length <= 5) {
        sections.push(`🤖 **Renovate / Bot Updates** (${botMrs.length}):\n\n${botMrs.map(formatMrLine).join('\n')}`);
      } else {
        const displayed = botMrs.slice(0, 5);
        const remaining = botMrs.length - 5;
        sections.push(
          `🤖 **Renovate / Bot Updates** (${botMrs.length}, showing top 5 ready/recent):\n\n` +
          `${displayed.map(formatMrLine).join('\n')}\n\n` +
          `_...and ${remaining} more bot MRs (use \`/mrs all\` to view all, or \`/mrs bots\` for only bot MRs)_`
        );
      }
    }

    return `📋 **Open Merge Requests** (${mrs.length} total: ${humanMrs.length} human, ${botMrs.length} bot):\n\n${sections.join('\n\n')}`;
  }

  async getOrFetchMrsText({ force = false, mode = 'default' } = {}) {
    const data = await this.getOrFetchMrsData({ force });
    return this.formatMrsText(data, mode);
  }

  async executeCachedCommand(event, { name, getOrFetch, getCached, errorLabel }) {
    log(`Executing /${name} in ${event.conversationId}...`);
    try {
      const cacheObj = this[`${name}Cache`];
      const cached = typeof getCached === 'function' ? getCached() : cacheObj?.text;
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

  async executeMrsCommand(event, args = []) {
    const mode = getMrsMode(args);
    await this.executeCachedCommand(event, {
      name: 'mrs',
      getCached: () => (this.mrsCache.data ? this.formatMrsText(this.mrsCache.data, mode) : null),
      getOrFetch: (opts) => this.getOrFetchMrsText({ ...opts, mode }),
      errorLabel: 'Group MRs lookup',
    });
  }

  async getOrFetchAlertsData({ force = false } = {}) {
    if (!this.opsgenie?.isConfigured()) {
      return {
        onCallAlerts: [],
        supportAlerts: [],
        onCallError: 'OpsGenie not configured',
        supportError: 'OpsGenie not configured',
      };
    }
    const now = Date.now();
    if (!force && this.alertsCache.data && now - this.alertsCache.timestamp < this.cacheTtlMs) {
      return this.alertsCache.data;
    }
    if (this.alertsCache.loading) {
      return await this.alertsCache.loading;
    }

    this.alertsCache.loading = (async () => {
      try {
        const data = await this.opsgenie.getAllOpenAlerts();
        this.alertsCache.data = data;
        this.alertsCache.timestamp = Date.now();
        return data;
      } catch (err) {
        if (this.alertsCache.data) {
          log(`Failed to refresh /alerts cache (${err.message}), serving stale cache`);
          return this.alertsCache.data;
        }
        throw err;
      } finally {
        this.alertsCache.loading = null;
      }
    })();

    return await this.alertsCache.loading;
  }

  async getOrFetchAlertsText({ force = false, mode = 'all' } = {}) {
    const data = await this.getOrFetchAlertsData({ force });
    return formatAlertsText(data, mode);
  }

  async executeAlertsCommand(event, args = []) {
    if (!this.opsgenie?.isConfigured()) {
      await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.failure);
      await sendReply(event.conversationId, event, '❌ OpsGenie integration is not configured.');
      return;
    }

    const sub = (args[0] || '').toLowerCase().replace(/^-+/, '');
    let mode = 'all';
    if (sub === 'oncall' || sub === 'on-call' || sub === 'call') {
      mode = 'oncall';
    } else if (sub === 'support' || sub === 'sup') {
      mode = 'support';
    }

    await this.executeCachedCommand(event, {
      name: 'alerts',
      getCached: () => (this.alertsCache.data ? formatAlertsText(this.alertsCache.data, mode) : null),
      getOrFetch: (opts) => this.getOrFetchAlertsText({ ...opts, mode }),
      errorLabel: 'OpsGenie alerts lookup',
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

  async executeLeaderboardCommand(event) {
    log(`Executing /leaderboard in ${event.conversationId}...`);
    await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.success);

    if (!this.userInteractions || this.userInteractions.size === 0) {
      await sendReply(
        event.conversationId,
        event,
        '🏆 **Bot Interaction Leaderboard**:\n\n_No interactions recorded yet._'
      );
      return;
    }

    const sortedUsers = [...this.userInteractions.values()].sort((a, b) => (b.count || 0) - (a.count || 0));

    const medals = ['🥇', '🥈', '🥉'];
    const lines = [];

    for (let i = 0; i < sortedUsers.length; i++) {
      const u = sortedUsers[i];
      const rankBadge = i < medals.length ? medals[i] : `\`#${i + 1}\``;

      const topCmds = Object.entries(u.commands || {})
        .sort(([, a], [, b]) => b - a)
        .slice(0, 3)
        .map(([cmd, cnt]) => `${cmd} (${cnt})`)
        .join(', ');

      const cmdBreakdown = topCmds ? ` _(top: ${topCmds})_` : '';
      lines.push(`${rankBadge} **${u.name}**: ${u.count} interaction${u.count === 1 ? '' : 's'}${cmdBreakdown}`);
    }

    const text = `🏆 **Bot Interaction Leaderboard**:\n\n${lines.join('\n')}`;
    await sendReply(event.conversationId, event, text);
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

    this.recordUserInteraction(event, command);

    // React immediately with eyes emoji to acknowledge command receipt
    await this.setCommandReaction(event.conversationId, event.messageId, COMMAND_REACTIONS.pending);

    if (command === '/approve') {
      await this.executeApproveCommand(event, args);
    } else if (command === '/rebase') {
      await this.executeRebaseCommand(event, args);
    } else if (command === '/status') {
      await this.executeStatusCommand(event, args);
    } else if (command === '/mrs') {
      await this.executeMrsCommand(event, args);
    } else if (command === '/alerts' || command === '/opsgenie') {
      await this.executeAlertsCommand(event, args);
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
    } else if (command === '/leaderboard') {
      await this.executeLeaderboardCommand(event);
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
    log('Precomputing /mrs, /alerts, /sprint, and /meetings cache in background...');
    await Promise.allSettled([
      this.getOrFetchMrsData({ force: true }).catch((err) => log(`Precompute /mrs failed: ${err.message}`)),
      this.getOrFetchAlertsData({ force: true }).catch((err) => log(`Precompute /alerts failed: ${err.message}`)),
      this.getOrFetchSprintText({ force: true }).catch((err) => log(`Precompute /sprint failed: ${err.message}`)),
      this.getOrFetchMeetingsText({ force: true }).catch((err) => log(`Precompute /meetings failed: ${err.message}`)),
    ]);
    log('Precompute /mrs, /alerts, /sprint, and /meetings cache completed');
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
