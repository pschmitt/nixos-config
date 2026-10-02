---
name: browser-passkey
description: >-
  Authenticate automated browser sessions (Playwright MCP) using WebAuthn passkeys
  stored in rbw / Vaultwarden. Use whenever an automated browser task encounters
  a passkey, WebAuthn, or FIDO2 login challenge.
---

# Browser Passkey Authentication

Use this skill when an automated browser session driven by Playwright MCP
(`playwright-fnuc`, `playwright-rofl-13`, `playwright-rofl-14`) encounters a
WebAuthn passkey or FIDO2 login challenge.

## Why this is needed

In containerized or remote browser environments, physical USB keys, Bluetooth
proximity checks for phone passkeys (FIDO2 caBLE), and platform authenticators
(Windows Hello, Touch ID) are unavailable.

Instead, we use Chromium's DevTools Protocol (`WebAuthn` domain) to instantiate
a virtual CTAP2 authenticator in the browser context and seed it with the
passkey private key stored in `rbw` / Vaultwarden. With
`automaticPresenceSimulation: true` and `isUserVerified: true`, Chromium
automatically and silently signs the WebAuthn challenge with zero human interaction.

## Prerequisites

1. **`rbw` unlocked:** Verify `rbw unlocked`. If locked, follow the unlock flow
   in the [rbw skill](file:///home/pschmitt/devel/private/pschmitt/nixos-config.git/home-manager/devel/skills/rbw/SKILL.md)
   (sending the Home Assistant phone notification).
2. **Playwright MCP tool:** The Playwright MCP server must expose `browser_run_code_unsafe`.

## Workflow

### Step 1: Navigate to the target login page

Use standard `browser_navigate` to load the login page (e.g. `https://auth.example.com` or `https://github.com/login`).

### Step 2: Inject the passkey into the active page

Invoke `browser_run_code_unsafe` with the following JavaScript snippet, replacing
`"ENTRY_NAME"` with the Bitwarden vault item name (e.g. `"Authelia"`, `"GitHub"`,
`"Google"`):

```javascript
async (page) => {
  const { execSync } = require('child_process');

  // Format credentialId: if UUID string, convert hex bytes to base64; otherwise convert base64url to base64
  const formatCredentialId = (id) => {
    if (!id) return '';
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (uuidRegex.test(id)) {
      return Buffer.from(id.replace(/-/g, ''), 'hex').toString('base64');
    }
    let b64 = id.replace(/-/g, '+').replace(/_/g, '/');
    while (b64.length % 4) b64 += '=';
    return b64;
  };

  // Convert base64url strings to standard base64 for CDP
  const b64 = (s) =>
    s ? s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4) : '';

  // 1. Fetch decrypted entry from rbw
  const entryName = "ENTRY_NAME";
  const raw = execSync(`rbw get --raw "${entryName}"`, { encoding: 'utf8' });
  const entry = JSON.parse(raw);
  const creds = entry.data?.fido2_credentials || [];

  if (!creds.length) {
    throw new Error(`No passkeys found in rbw entry "${entryName}"`);
  }

  // Pick the credential matching the current domain, or default to the first
  const currentHost = new URL(page.url()).hostname;
  const cred = creds.find(c => currentHost.endsWith(c.rp_id)) || creds[0];

  // 2. Attach CDP session to the page
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('WebAuthn.enable');

  // 3. Create virtual CTAP2 authenticator with auto-presence and backup flags
  const { authenticatorId } = await cdp.send('WebAuthn.addVirtualAuthenticator', {
    options: {
      protocol: 'ctap2',
      transport: 'internal',
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation: true,
      defaultBackupEligibility: true,
      defaultBackupState: true,
    }
  });

  // 4. Inject the passkey credential
  await cdp.send('WebAuthn.addCredential', {
    authenticatorId,
    credential: {
      credentialId: formatCredentialId(cred.credential_id),
      rpId: cred.rp_id,
      privateKey: b64(cred.key_value),
      userHandle: b64(cred.user_handle),
      isResidentCredential: true,
      signCount: 0,
      backupEligibility: true,
      backupState: true,
    }
  });

  return {
    status: 'passkey_ready',
    rpId: cred.rp_id,
    authenticatorId
  };
}
```

### Step 3: Trigger the passkey login

Use `browser_click` on the site's "Sign in with a passkey" or "Use security key" button.

When the site calls `navigator.credentials.get()`, Chromium's virtual authenticator
resolves the assertion immediately in the background using the injected key.

## Technical Details & Key Formats

* **Private Key Format:** In `rbw`, `data.fido2_credentials[i].key_value` stores
  an ASN.1 PKCS#8 DER private key (`id-ecPublicKey` on curve `prime256v1`) in
  URL-safe Base64. CDP expects standard Base64 PKCS#8 DER, so simple padding and
  character substitution (`-` $\rightarrow$ `+`, `_` $\rightarrow$ `/`) is all that is required.
* **Session Scope:** Virtual authenticators in Chromium are scoped to the active CDP
  session. Because `page.context().newCDPSession(page)` attaches to the persistent
  Playwright MCP browser context, the authenticator remains alive and active for all
  subsequent page interactions and navigations.
* **Security:** Keep private keys out of the conversational context. Do not dump
  the decrypted JSON or private key material into model output or log files.
