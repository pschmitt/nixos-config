import fs from 'node:fs';
import { extractMessageAuth, getMessageAuthStatus } from 'msteams-mcp/dist/auth/token-extractor.js';
import { refreshTokensViaHttp } from 'msteams-mcp/dist/auth/token-refresh-http.js';
import { signInViaBrowserDaemon } from 'msteams-mcp/dist/auth/token-refresh.js';
import { writeSessionState } from 'msteams-mcp/dist/auth/session-store.js';

const log = (...args) => console.error(new Date().toISOString(), '[auth]', ...args);

export class AuthManager {
  constructor(config) {
    this.config = config;
    this.credentialsFile = config.teams?.credentials_file || null;
    this.credentialsLoaded = false;
    this.refreshTimer = null;

    if (config.browser_daemon?.url) {
      process.env.TEAMS_MCP_BROWSER_DAEMON_URL = config.browser_daemon.url;
    }
    if (config.browser_daemon?.profile) {
      process.env.TEAMS_MCP_BROWSER_DAEMON_PROFILE = config.browser_daemon.profile;
    }
    if (config.browser_daemon?.secret_file) {
      process.env.BROWSER_DAEMON_SECRET_FILE = config.browser_daemon.secret_file;
    }
  }

  loadCredentialsFile({ force = false } = {}) {
    if (!this.credentialsFile || !fs.existsSync(this.credentialsFile)) {
      return null;
    }
    try {
      const stat = fs.statSync(this.credentialsFile);
      if (!force && this.credentialsLoaded && this.lastLoadedCredentialsMtime && stat.mtimeMs <= this.lastLoadedCredentialsMtime) {
        log(`Credentials file ${this.credentialsFile} unmodified on disk, preserving active session`);
        return null;
      }
      this.lastLoadedCredentialsMtime = stat.mtimeMs;
      const raw = fs.readFileSync(this.credentialsFile, 'utf8').trim();
      if (!raw) return null;
      const data = JSON.parse(raw);

      // If full session state (cookies and origins from msteams-mcp session-state)
      if (data.cookies && data.origins) {
        log(`Loaded full session state from ${this.credentialsFile}`);
        // Ensure DISCOVER-REGION-GTM exists in localStorage so msteams-mcp calendar-api can extract region
        const origin = data.origins.find((o) => o.origin?.includes('teams.'));
        if (origin && !origin.localStorage?.some((item) => item.name?.includes('DISCOVER-REGION-GTM'))) {
          origin.localStorage = origin.localStorage || [];
          origin.localStorage.push({
            name: 'DISCOVER-REGION-GTM',
            value: JSON.stringify({
              item: {
                middleTier: 'https://teams.microsoft.com/api/mt/emea',
                chatServiceAfd: 'https://teams.microsoft.com/api/chatsvc/emea',
                chatSvcAggAfd: 'https://teams.microsoft.com/api/csa/emea',
              },
            }),
          });
        }
        writeSessionState(data);
        return extractMessageAuth(data);
      }

      // If flat credentials format
      if (data.skypeToken && data.authToken) {
        log(`Loaded token credentials from ${this.credentialsFile}`);
        return {
          skypeToken: data.skypeToken,
          authToken: data.authToken,
          userMri: data.userMri || null,
        };
      }
    } catch (err) {
      log(`Error reading credentials file ${this.credentialsFile}: ${err.message}`);
    }
    return null;
  }

  async ensureValidAuth({ forceDaemon = false } = {}) {
    // 1. Initial seed from credentials file if session not yet loaded
    let fileAuth = null;
    if (!this.credentialsLoaded) {
      fileAuth = this.loadCredentialsFile();
      this.credentialsLoaded = true;
    }

    const status = getMessageAuthStatus();
    log(`Current messaging auth status: hasToken=${status.hasToken}, minutesRemaining=${status.minutesRemaining ?? 'unknown'}`);

    if (!forceDaemon && status.hasToken && (status.minutesRemaining ?? 0) > 15) {
      const auth = extractMessageAuth();
      if (auth) return auth;
      if (fileAuth) return fileAuth;
    }

    // 2. Try HTTP refresh (uses the refresh token stored in session state)
    if (!forceDaemon) {
      log('Attempting HTTP token refresh...');
      try {
        const httpResult = await refreshTokensViaHttp();
        if (httpResult.ok) {
          const auth = extractMessageAuth();
          if (auth) {
            log('HTTP token refresh succeeded');
            return auth;
          }
        } else {
          log(`HTTP token refresh failed: ${httpResult.error?.message || 'unknown error'}`);
          // If refresh failed and we hadn't re-seeded recently, re-read credentials file once
          if (!fileAuth && this.credentialsFile) {
            log('Re-reading credentials file in case secret was updated...');
            this.loadCredentialsFile();
          }
        }
      } catch (err) {
        log(`HTTP token refresh threw: ${err.message}`);
      }
    }

    // 3. Fallback to browser-daemon only if explicitly configured
    if (this.config.browser_daemon?.url) {
      log(`Attempting sign-in via browser-daemon profile "${this.config.browser_daemon.profile}"...`);
      try {
        const daemonResult = await signInViaBrowserDaemon();
        if (daemonResult.ok) {
          const auth = extractMessageAuth();
          if (auth) {
            log('Sign-in via browser-daemon succeeded');
            return auth;
          }
        } else {
          log(`Browser-daemon sign-in returned error: ${daemonResult.error?.message || 'unknown error'}`);
        }
      } catch (err) {
        log(`Browser-daemon sign-in threw: ${err.message}`);
      }
    }

    // 4. Return fileAuth if present
    if (fileAuth) {
      return fileAuth;
    }

    // 5. Final attempt from cached state
    const fallbackAuth = extractMessageAuth();
    if (fallbackAuth) {
      log('Using cached session state despite warnings');
      return fallbackAuth;
    }

    throw new Error('No valid Teams session credentials found and automatic refresh failed.');
  }

  startProactiveRefresh(intervalMinutes = 5) {
    if (this.refreshTimer) clearInterval(this.refreshTimer);

    this.refreshTimer = setInterval(async () => {
      try {
        const status = getMessageAuthStatus();
        if (!status.hasToken || (status.minutesRemaining ?? 0) < 60) {
          log(`Proactive token refresh triggered (hasToken=${status.hasToken}, minutesRemaining=${status.minutesRemaining ?? 0})`);
          await this.ensureValidAuth();
        }
      } catch (err) {
        log(`Proactive token refresh failed: ${err.message}`);
      }
    }, intervalMinutes * 60 * 1000);

    if (this.refreshTimer.unref) this.refreshTimer.unref();
  }

  stop() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }
}
