#!/usr/bin/env node
import { loadConfig } from './config.mjs';
import { AuthManager } from './auth.mjs';
import { GitLabClient } from './gitlab.mjs';
import { JiraClient } from './jira.mjs';
import { OpsGenieClient } from './opsgenie.mjs';
import { TrouterClient } from './trouter.mjs';
import { MergeRequestWatcher } from './watcher.mjs';

const log = (...args) => console.error(new Date().toISOString(), '[main]', ...args);

// CLI args
const args = process.argv.slice(2);
let configPath = null;
const configIdx = args.indexOf('--config');
if (configIdx !== -1 && args[configIdx + 1]) {
  configPath = args[configIdx + 1];
}

const VERBOSE = args.includes('--verbose');
const ALL = VERBOSE || args.includes('--all');
const JSON_MODE = args.includes('--json');
const COLOR = !JSON_MODE && process.stdout.isTTY && !process.env.NO_COLOR;

const paint = (code, text) => (COLOR ? `\x1b[${code}m${text}\x1b[0m` : text);
const dim = (text) => paint('2', text);
const NICK_COLORS = [31, 32, 33, 34, 35, 36, 91, 92, 93, 94, 95, 96];

function nick(name) {
  let hash = 0;
  for (const ch of name) hash = (hash * 31 + ch.codePointAt(0)) >>> 0;
  return paint(NICK_COLORS[hash % NICK_COLORS.length], name);
}

function clock(time) {
  const d = time ? new Date(time) : new Date();
  return d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}

const names = new Map();

function channelLabel(event, selfMri) {
  if (event.threadTopic) return `#${event.threadTopic}`;
  const dm = /^19:([0-9a-f-]{36})_([0-9a-f-]{36})@unq\.gbl\.spaces$/.exec(event.conversationId ?? '');
  if (dm) {
    const selfOid = selfMri?.split(':').pop();
    const otherMri = `8:orgid:${dm[1] === selfOid ? dm[2] : dm[1]}`;
    return `@${names.get(otherMri) ?? otherMri.slice(8, 16)}`;
  }
  return `#${(event.conversationId ?? '?').replace(/^19:/, '').slice(0, 16)}`;
}

function formatHuman(event, selfMri) {
  if (event.fromMri && event.from) names.set(event.fromMri, event.from);
  const prefix = `${dim(`[${clock(event.time)}]`)} ${channelLabel(event, selfMri)}`;
  const who = event.from || names.get(event.fromMri) || event.fromMri || '?';

  if (event.messageType === 'Control/Typing') return `${prefix} ${dim(`* ${who} is typing`)}`;
  if (event.messageType && !event.content) return `${prefix} ${dim(`* ${event.kind} ${event.messageType ?? ''}`.trim())}`;

  const tag = event.kind === 'MessageUpdate' ? dim(event.content ? ' (edited)' : ' (deleted)') : '';
  const body = (event.content ?? '').replace(/\n+/g, '\n    ');
  return `${prefix} <${nick(who)}>${tag} ${body}`;
}

async function main() {
  log('Starting teams-live...');
  const config = loadConfig(configPath);

  log(`Watched conversations: ${config.conversations.map((c) => `${c.name || ''} (${c.id})`).join(', ')}`);
  if (config.browser_daemon.url) {
    log(`Browser-daemon configured: ${config.browser_daemon.url} (profile: ${config.browser_daemon.profile})`);
  }
  log(`GitLab host: ${config.gitlab.host} (token present: ${!!config.gitlab.token})`);

  const authManager = new AuthManager(config);
  const gitlab = new GitLabClient(config.gitlab);
  const jira = new JiraClient(config.jira);
  const opsgenie = new OpsGenieClient(config.opsgenie);
  const watcher = new MergeRequestWatcher({ config, gitlab, jira, opsgenie, authManager });

  let trouter = null;
  let stopping = false;

  const cleanup = async (signal = 'SIGTERM') => {
    if (stopping) return;
    stopping = true;
    log(`Shutting down teams-live (signal: ${signal})...`);
    try {
      await watcher.sendShutdownAnnouncement(signal);
    } catch (err) {
      log(`Failed to send shutdown announcement: ${err.message}`);
    }
    watcher.stop();
    authManager.stop();
    if (trouter) trouter.close();
    process.exit(0);
  };

  process.on('SIGINT', () => cleanup('SIGINT'));
  process.on('SIGTERM', () => cleanup('SIGTERM'));

  // Initial auth check / self-heal
  let currentAuth = await authManager.ensureValidAuth();
  watcher.setSelfMri(currentAuth.userMri);
  authManager.startProactiveRefresh(config.teams.token_refresh_interval_minutes);

  // Historical scan
  try {
    await watcher.watchHistory();
  } catch (err) {
    log(`Initial history scan failed: ${err.message}`);
  }

  // Start polling GitLab
  watcher.startPolling();

  // Startup announcement (self-chat only)
  watcher.sendStartupAnnouncement().catch((err) => {
    log(`Startup announcement failed: ${err.message}`);
  });

  trouter = new TrouterClient({
    verbose: VERBOSE,
    all: ALL,
    onEvent: (event) => {
      if (JSON_MODE) {
        console.log(JSON.stringify(event));
      } else {
        console.log(formatHuman(event, currentAuth.userMri));
      }
      watcher.handleIncomingEvent(event);
    },
  });

  // Main reconnect loop
  while (!stopping) {
    try {
      currentAuth = await authManager.ensureValidAuth();
      watcher.setSelfMri(currentAuth.userMri);
      await trouter.connect(currentAuth);
    } catch (err) {
      log(`Connection error: ${err.message}`);
      // If error might be auth-related, force browser-daemon reauth on next round
      if (err.message.includes('401') || err.message.includes('Unauthorized') || err.message.includes('auth')) {
        try {
          currentAuth = await authManager.ensureValidAuth({ forceDaemon: true });
        } catch (e) {
          log(`Failed to re-authenticate: ${e.message}`);
        }
      }
    }

    if (!stopping) {
      const waitSec = config.teams.reconnect_interval_seconds || 5;
      log(`Reconnecting in ${waitSec} seconds...`);
      await new Promise((r) => setTimeout(r, waitSec * 1000));
    }
  }
}

main().catch((err) => {
  console.error('Fatal error in teams-live:', err);
  process.exit(1);
});
