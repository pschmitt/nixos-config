#!/usr/bin/env node
// Answer the passkey requests of a Chromium session with the vault's passkey,
// for agents signing in without a person (Microsoft, Authelia, ...).
//
//   agent-passkey.mjs CDP_HTTP_URL [--timeout SECONDS]
//
// CDP_HTTP_URL is the browser's debugging address, e.g. http://127.0.0.1:PORT
// (`browser-daemon session list --json` has the port; forward it with ssh -L
// for a session on another node). Start it in the background BEFORE the sign-in
// and stop it afterwards. Every navigator.credentials.get() of every page and
// frame is signed outside the browser by `rbw passkey assert`, with the origin
// taken from the browser's target list (never from page script). Unlike
// `rbw passkey inject` nothing is armed on one page, so it survives sign-in
// flows that hop across origins and ask for the assertion the moment the page
// loads (Microsoft's login.microsoft.com/common/bridge/fido, which cannot be
// reloaded). Autofill (conditional) requests are left to the browser.
import { execFile } from "node:child_process";

const args = process.argv.slice(2);
const base = args.find((a) => !a.startsWith("--"));
const ti = args.indexOf("--timeout");
const timeout = ti >= 0 ? Number(args[ti + 1]) : 600;
if (!base) {
  console.error("usage: agent-passkey.mjs CDP_HTTP_URL [--timeout SECONDS]");
  process.exit(2);
}

const HOOK = `(() => {
  const c = navigator.credentials;
  if (!c || c.__rbwHooked || typeof globalThis.__rbwPasskey !== "function") return;
  Object.defineProperty(c, "__rbwHooked", { value: true });
  const get = c.get.bind(c), waiting = new Map();
  const b64url = (b) => btoa(String.fromCharCode(...new Uint8Array(b.buffer ? b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) : b))).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
  const bytes = (s) => { s = s.replace(/-/g, "+").replace(/_/g, "/"); s += "===".slice((s.length + 3) % 4); return Uint8Array.from(atob(s), (ch) => ch.charCodeAt(0)).buffer; };
  const own = (o, props) => { for (const [k, v] of Object.entries(props)) Object.defineProperty(o, k, { value: v, enumerable: true }); return o; };
  const credential = (a) => {
    const r = a.response;
    const response = own(Object.create(AuthenticatorAssertionResponse.prototype), {
      clientDataJSON: bytes(r.clientDataJSON), authenticatorData: bytes(r.authenticatorData),
      signature: bytes(r.signature), userHandle: r.userHandle ? bytes(r.userHandle) : null,
    });
    const cred = own(Object.create(PublicKeyCredential.prototype), {
      id: a.id, rawId: bytes(a.rawId), type: "public-key", response, authenticatorAttachment: a.authenticatorAttachment || "platform",
    });
    Object.defineProperty(cred, "getClientExtensionResults", { value: () => ({}) });
    Object.defineProperty(cred, "toJSON", { value: () => ({ id: a.id, rawId: a.id, type: "public-key", authenticatorAttachment: a.authenticatorAttachment || "platform", response: r, clientExtensionResults: {} }) });
    return cred;
  };
  globalThis.__rbwPasskeyAnswer = (id, answer) => { const go = waiting.get(id); waiting.delete(id); go?.(answer); };
  c.get = function (opts) {
    const pk = opts && opts.publicKey;
    if (!pk || opts.mediation === "conditional") return get(opts);
    const id = Math.random().toString(36).slice(2);
    let req;
    try { req = { id, rpId: pk.rpId || location.hostname, challenge: b64url(pk.challenge), allow: (pk.allowCredentials || []).map((x) => b64url(x.id)) }; } catch { return get(opts); }
    return new Promise((go) => {
      waiting.set(id, go);
      setTimeout(() => globalThis.__rbwPasskeyAnswer(id, null), 120000);
      try { globalThis.__rbwPasskey(JSON.stringify(req)); } catch { globalThis.__rbwPasskeyAnswer(id, null); }
    }).then((answer) => answer ? credential(answer) : get(opts));
  };
})()`;

const version = await (await fetch(`${base.replace(/\/$/, "")}/json/version`)).json();
const ws = new WebSocket(version.webSocketDebuggerUrl);
let seq = 0;
const pending = new Map();
const urls = new Map(); // targetId -> url, from the browser itself
const sessions = new Map(); // sessionId -> targetId
const call = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
  const id = ++seq;
  pending.set(id, { resolve, reject });
  ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
});

function sign(session, request) {
  const targetId = sessions.get(session);
  let origin;
  try { origin = new URL(urls.get(targetId)).origin; } catch { return Promise.resolve(null); }
  const a = ["passkey", "assert", "--rp-id", request.rpId, "--origin", origin, "--challenge", request.challenge];
  for (const id of request.allow) a.push("--allow", id);
  return new Promise((resolve) => {
    execFile("rbw", a, { encoding: "utf8", timeout: 60000 }, (err, stdout, stderr) => {
      if (err) { console.error(`rbw: ${(stderr || String(err)).trim().split("\n").pop()}`); return resolve(null); }
      try { resolve(JSON.parse(stdout)); } catch { resolve(null); }
    });
  });
}

async function setup(sessionId, info) {
  sessions.set(sessionId, info.targetId);
  urls.set(info.targetId, info.url);
  try {
    await call("Runtime.enable", {}, sessionId).catch(() => {}); // bindings only fire once Runtime is enabled
    await call("Runtime.addBinding", { name: "__rbwPasskey" }, sessionId);
    await call("Page.enable", {}, sessionId).catch(() => {});
    await call("Page.addScriptToEvaluateOnNewDocument", { source: HOOK, runImmediately: true }, sessionId);
    await call("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: true, flatten: true }, sessionId).catch(() => {});
  } finally {
    await call("Runtime.runIfWaitingForDebugger", {}, sessionId).catch(() => {});
  }
}

ws.onmessage = async (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && pending.has(msg.id)) {
    const p = pending.get(msg.id);
    pending.delete(msg.id);
    return msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
  }
  if (msg.method === "Target.attachedToTarget") {
    const { sessionId, targetInfo } = msg.params;
    if (["page", "iframe"].includes(targetInfo.type)) setup(sessionId, targetInfo);
    else call("Runtime.runIfWaitingForDebugger", {}, sessionId).catch(() => {});
  } else if (msg.method === "Target.targetInfoChanged") {
    urls.set(msg.params.targetInfo.targetId, msg.params.targetInfo.url);
  } else if (msg.method === "Runtime.bindingCalled" && msg.params.name === "__rbwPasskey") {
    const request = JSON.parse(msg.params.payload);
    const answer = await sign(msg.sessionId, request);
    console.error(answer ? `signed for ${request.rpId}` : `no assertion for ${request.rpId}`);
    await call("Runtime.evaluate", { expression: `globalThis.__rbwPasskeyAnswer(${JSON.stringify(request.id)}, ${JSON.stringify(answer)})` }, msg.sessionId).catch(() => {});
  }
};
await new Promise((r) => (ws.onopen = r));
await call("Target.setDiscoverTargets", { discover: true });
await call("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
console.error("agent-passkey: ready");
setTimeout(() => process.exit(0), timeout * 1000);
