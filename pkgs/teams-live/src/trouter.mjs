import { randomUUID } from 'node:crypto';
import { gunzipSync } from 'node:zlib';

const TROUTER = 'https://go.trouter.teams.microsoft.com';
const REGISTRAR = 'https://teams.microsoft.com/registrar/prod/V2/registrations';
const CLIENT_VERSION = '49/25113001312';
const TC = JSON.stringify({ cv: '2024.23.01.2', ua: 'TeamsCDL', hr: '', v: CLIENT_VERSION });
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0 Teams/24165.1410.2974.6689/49';
const REGISTRATION_TTL = 86400;
const MESSAGE_KINDS = new Set(['NewMessage', 'MessageUpdate']);
const isContentType = (t) => t === 'Text' || t?.startsWith('RichText');

const log = (...args) => console.error(new Date().toISOString(), '[trouter]', ...args);

function connectQuery(info, epid) {
  const params = new URLSearchParams({ v: 'v4', ...info.connectparams, tc: TC, con_num: `${Date.now()}_1`, epid });
  if (info.ccid) params.set('ccid', info.ccid);
  params.set('auth', 'true');
  params.set('timeout', '40');
  return params.toString();
}

async function register(auth, epid, appId, templateKey, path) {
  const res = await fetch(REGISTRAR, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Skypetoken': auth.skypeToken,
      Authorization: `Bearer ${auth.authToken}`,
    },
    body: JSON.stringify({
      clientDescription: {
        appId,
        aesKey: '',
        languageId: 'en-US',
        platform: 'edge',
        templateKey,
        platformUIVersion: CLIENT_VERSION,
      },
      registrationId: appId === 'TeamsCDLWebWorker' ? epid : randomUUID(),
      nodeId: '',
      transports: { TROUTER: [{ context: '', path, ttl: REGISTRATION_TTL }] },
    }),
  });
  log(`registrar ${appId}: HTTP ${res.status}`);
}

function decodeBody(request) {
  let body = request.body ?? '';
  if (request.headers?.['X-Microsoft-Skype-Content-Encoding'] === 'gzip') {
    body = gunzipSync(Buffer.from(body, 'base64')).toString('utf8');
  }
  if (!body) return null;
  let obj = JSON.parse(body);
  if (obj.cp) obj = JSON.parse(gunzipSync(Buffer.from(obj.cp, 'base64')).toString('utf8'));
  else if (obj.gp) obj = JSON.parse(Buffer.from(obj.gp, 'base64').toString('utf8'));
  return obj;
}

function stripHtml(html) {
  return String(html ?? '')
    .replace(/<blockquote[\s\S]*?<\/blockquote>/gi, '')
    .replace(/<div[^>]*itemtype="http:\/\/schema\.skype\.com\/Reply"[\s\S]*?<\/div>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/li>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .trim();
}

function extractLinks(html) {
  if (!html) return [];
  const withoutQuotes = String(html)
    .replace(/<blockquote[\s\S]*?<\/blockquote>/gi, '')
    .replace(/<div[^>]*itemtype="http:\/\/schema\.skype\.com\/Reply"[\s\S]*?<\/div>/gi, '');
  return [...withoutQuotes.matchAll(/href="([^"]+)"/g)].map((m) => m[1]);
}

function toEvent(url, body, { verbose = false, all = false } = {}) {
  const service = url.split('/').pop();
  if (service === 'messaging' && body?.type === 'EventMessage') {
    const r = body.resource ?? {};
    if (!all && !(MESSAGE_KINDS.has(body.resourceType) && isContentType(r.messagetype))) return null;

    let convId = r.conversationLink?.split('/conversations/').pop() ?? r.to;
    if (convId) {
      try {
        convId = decodeURIComponent(convId);
      } catch {}
    }

    return {
      kind: body.resourceType,
      time: r.composetime ?? r.originalarrivaltime ?? body.time,
      conversationId: convId,
      threadTopic: r.threadtopic,
      from: r.imdisplayname,
      fromMri: r.from?.split('/contacts/').pop(),
      messageType: r.messagetype,
      messageId: r.id,
      clientMessageId: r.clientmessageid,
      content: isContentType(r.messagetype) ? stripHtml(r.content) : undefined,
      rawHtml: isContentType(r.messagetype) ? r.content : undefined,
      links: isContentType(r.messagetype) ? extractLinks(r.content) : undefined,
      raw: verbose ? body : undefined,
    };
  }
  return all ? { kind: service, raw: verbose ? body : undefined } : null;
}

export class TrouterClient {
  constructor({ onEvent, verbose = false, all = false } = {}) {
    this.onEvent = onEvent;
    this.verbose = verbose;
    this.all = all;
    this.ws = null;
    this.pingTimer = null;
    this.registrationTimer = null;
  }

  async connect(auth) {
    const epid = randomUUID();

    const infoRes = await fetch(`${TROUTER}/v4/a?epid=${epid}`, {
      method: 'POST',
      headers: { 'X-Skypetoken': auth.skypeToken, 'Content-Length': '0' },
    });
    if (!infoRes.ok) throw new Error(`trouter info: HTTP ${infoRes.status} ${await infoRes.text()}`);
    const info = await infoRes.json();
    const socketio = info.socketio ?? `${TROUTER}/`;
    const query = connectQuery(info, epid);

    const sidRes = await fetch(`${socketio}socket.io/1/?${query}`, { headers: { 'X-Skypetoken': auth.skypeToken } });
    if (!sidRes.ok) throw new Error(`trouter session: HTTP ${sidRes.status} ${await sidRes.text()}`);
    const sessionId = (await sidRes.text()).split(':')[0];

    const wsUrl = `${socketio.replace(/^http/, 'ws')}socket.io/1/websocket/${sessionId}?${query}`;
    const ws = new WebSocket(wsUrl, { headers: { 'X-Skypetoken': auth.skypeToken, 'User-Agent': USER_AGENT } });
    this.ws = ws;

    let seq = 1;
    const send = (frame) => ws.send(frame);
    const sendCommand = (obj) => send(`5:${seq++}+::${JSON.stringify(obj)}`);
    let lastLossRegistration = 0;

    return new Promise((resolve, reject) => {
      ws.addEventListener('open', () => log('websocket open'));
      ws.addEventListener('error', (e) => reject(new Error(`websocket error: ${e.message ?? e.type}`)));
      ws.addEventListener('close', (e) => {
        clearInterval(this.pingTimer);
        clearInterval(this.registrationTimer);
        log(`websocket closed (${e.code})`);
        resolve();
      });

      ws.addEventListener('message', async ({ data }) => {
        const frame = String(data);
        const type = frame[0];

        if (type === '1') {
          log('connected, authenticating');
          send(
            `5:::${JSON.stringify({
              name: 'user.authenticate',
              args: [
                {
                  headers: {
                    'X-Ms-Test-User': 'False',
                    Authorization: `Bearer ${auth.authToken}`,
                    'X-MS-Migration': 'True',
                  },
                  connectparams: info.connectparams,
                },
              ],
            })}`
          );
          const registerAll = () =>
            Promise.all([
              register(auth, epid, 'NextGenCalling', 'DesktopNgc_2.3:SkypeNgc', `${info.surl}NGCallManagerWin`),
              register(auth, epid, 'SkypeSpacesWeb', 'SkypeSpacesWeb_2.3', `${info.surl}SkypeSpacesWeb`),
              register(auth, epid, 'TeamsCDLWebWorker', 'TeamsCDLWebWorker_2.1', info.surl),
            ]).catch((err) => log(`registration failed: ${err.message}`));

          await registerAll();
          this.pingTimer = setInterval(() => sendCommand({ name: 'ping' }), 30_000);
          this.registrationTimer = setInterval(registerAll, (REGISTRATION_TTL - 60) * 1000);
          return;
        }

        if (type === '3') {
          const payload = frame.split(':').slice(3).join(':');
          const request = JSON.parse(payload);
          if (request.status !== undefined) return;
          send(`3:::${JSON.stringify({ id: request.id, status: 200, body: '' })}`);
          try {
            const event = toEvent(request.url ?? '', decodeBody(request), {
              verbose: this.verbose,
              all: this.all,
            });
            if (event && this.onEvent) {
              this.onEvent(event);
            }
          } catch (err) {
            log(`could not decode event for ${request.url}: ${err.message}`);
          }
          return;
        }

        if (type === '5') {
          const obj = JSON.parse(frame.split(':').slice(3).join(':') || '{}');
          if (obj.name === 'trouter.message_loss') {
            if (Date.now() - lastLossRegistration < 30_000) return;
            lastLossRegistration = Date.now();
            log('server reported message loss, re-registering');
            await register(auth, epid, 'TeamsCDLWebWorker', 'TeamsCDLWebWorker_2.1', info.surl);
          } else if (this.verbose) {
            log(`control: ${frame}`);
          }
        }
      });
    });
  }

  close() {
    if (this.pingTimer) clearInterval(this.pingTimer);
    if (this.registrationTimer) clearInterval(this.registrationTimer);
    if (this.ws) {
      try {
        this.ws.close();
      } catch {}
      this.ws = null;
    }
  }
}
