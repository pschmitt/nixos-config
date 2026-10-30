import fs from 'node:fs';

function stripYamlComments(text) {
  return text
    .split('\n')
    .map((line) => {
      const idx = line.indexOf('#');
      if (idx === -1) return line;
      const quoteCount = (line.slice(0, idx).match(/["']/g) || []).length;
      return quoteCount % 2 === 0 ? line.slice(0, idx) : line;
    })
    .join('\n');
}

export function parseConfigFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Config file not found: ${filePath}`);
  }
  const raw = fs.readFileSync(filePath, 'utf8').trim();
  if (!raw) return {};

  try {
    return JSON.parse(raw);
  } catch (err) {
    try {
      const stripped = stripYamlComments(raw);
      return JSON.parse(stripped);
    } catch {
      throw new Error(`Failed to parse config file ${filePath} as JSON/YAML: ${err.message}`);
    }
  }
}

export function loadConfig(configPath) {
  let fileConfig = {};
  if (configPath) {
    fileConfig = parseConfigFile(configPath);
  } else if (process.env.TEAMS_LIVE_CONFIG) {
    fileConfig = parseConfigFile(process.env.TEAMS_LIVE_CONFIG);
  }

  const browserDaemon = {
    url: fileConfig.browser_daemon?.url || process.env.TEAMS_MCP_BROWSER_DAEMON_URL || '',
    profile: fileConfig.browser_daemon?.profile || process.env.TEAMS_MCP_BROWSER_DAEMON_PROFILE || 'work',
    secret_file: fileConfig.browser_daemon?.secret_file || process.env.BROWSER_DAEMON_SECRET_FILE || null,
  };

  let browserDaemonSecret = null;
  if (browserDaemon.secret_file && fs.existsSync(browserDaemon.secret_file)) {
    try {
      browserDaemonSecret = fs.readFileSync(browserDaemon.secret_file, 'utf8').trim();
    } catch (e) {
      console.warn(`Could not read browser-daemon secret file ${browserDaemon.secret_file}: ${e.message}`);
    }
  }

  const gitlab = {
    host: fileConfig.gitlab?.host || process.env.GITLAB_HOST || 'git.wiit.one',
    token_file: fileConfig.gitlab?.token_file || process.env.GITLAB_TOKEN_FILE || null,
    token: null,
    poll_interval_seconds: Number(fileConfig.gitlab?.poll_interval_seconds ?? process.env.TEAMS_GITLAB_INTERVAL ?? 60),
    history_limit: Number(fileConfig.gitlab?.history_limit ?? process.env.TEAMS_GITLAB_HISTORY ?? 50),
    notify_ci: fileConfig.gitlab?.notify_ci ?? true,
    notify_ci_on_failure: fileConfig.gitlab?.notify_ci_on_failure ?? true,
    notify_ci_on_success: fileConfig.gitlab?.notify_ci_on_success ?? true,
    notify_approval_lost: fileConfig.gitlab?.notify_approval_lost ?? true,
    notify_rebase: fileConfig.gitlab?.notify_rebase ?? true,
  };

  if (gitlab.token_file && fs.existsSync(gitlab.token_file)) {
    try {
      gitlab.token = fs.readFileSync(gitlab.token_file, 'utf8').trim();
    } catch (e) {
      console.warn(`Could not read GitLab token file ${gitlab.token_file}: ${e.message}`);
    }
  } else if (process.env.GITLAB_TOKEN) {
    gitlab.token = process.env.GITLAB_TOKEN.trim();
  }

  const teams = {
    reconnect_interval_seconds: Number(fileConfig.teams?.reconnect_interval_seconds ?? 5),
    token_refresh_interval_minutes: Number(fileConfig.teams?.token_refresh_interval_minutes ?? 60),
    credentials_file: fileConfig.teams?.credentials_file || process.env.TEAMS_CREDENTIALS_FILE || null,
  };

  let conversations = fileConfig.conversations;
  if (!conversations || !Array.isArray(conversations) || conversations.length === 0) {
    conversations = [
      {
        id: '48:notes',
        name: 'Notes (Self)',
        gitlab: true,
      },
    ];
  }

  return {
    browser_daemon: {
      ...browserDaemon,
      cluster_secret: browserDaemonSecret,
    },
    gitlab,
    teams,
    conversations,
  };
}
