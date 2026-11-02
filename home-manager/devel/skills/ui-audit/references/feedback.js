// Save-feedback probe for browser_run_code_unsafe. Edit the constants, then
// pass the whole file as `code`. It WRITES: point EDIT_URL at a record you
// created for the test, signed in as a throwaway account, never at real data.
// Each case runs in its own tab, closed without beforeunload, so a dirty form
// cannot block the MCP's own page. Errors, offline and latency are simulated
// with route interception; the server never sees them. The success and slow
// cases really save: FIELD ends up as "ui-audit <case> <n>", so a cleanup that
// checks the record's name before deleting it must accept that prefix.
async (page) => {
  const BASE = 'https://example.com';
  const EDIT_URL = '/app/projects/123/edit';
  const FIELD = 'Project name'; // label of a text field to change
  const SAVE = /Save changes/; // accessible name of the save button
  const WRITE = ['POST', 'PUT', 'PATCH', 'DELETE'];

  const visible = (p) => p.evaluate(() => [...document.querySelectorAll('[role=status],[role=alert],[aria-live],[class*=toast]')]
    .filter((e) => e.innerText.trim())
    .map((e) => { const y = Math.round(e.getBoundingClientRect().y); return `"${e.innerText.trim().replace(/\s+/g, ' ').slice(0, 70)}" y=${y} ${y >= 0 && y < innerHeight ? 'ONSCREEN' : 'OFFSCREEN'}`; }));
  const focus = (p) => p.evaluate(() => { const e = document.activeElement; return e ? (e.innerText || e.getAttribute('aria-label') || e.tagName).trim().replace(/\s+/g, ' ').slice(0, 30) : null; });

  const run = async (name, setup) => {
    const p = await page.context().newPage();
    await p.setViewportSize({ width: 1440, height: 900 });
    const dialogs = []; p.on('dialog', async (d) => { dialogs.push(`${d.type()}: ${d.message()}`); await d.dismiss(); });
    const r = { dialogs };
    let writes = 0;
    try {
      await p.route('**/*', async (rt) => {
        if (!WRITE.includes(rt.request().method())) return rt.continue();
        writes++;
        return setup.onWrite ? setup.onWrite(rt) : rt.continue();
      });
      await p.goto(BASE + EDIT_URL); await p.waitForLoadState('networkidle');
      await p.getByLabel(FIELD).fill(`ui-audit ${name} ${Date.now() % 10000}`);
      const btn = p.getByRole('button', { name: SAVE }); await btn.scrollIntoViewIfNeeded();
      if (setup.offline) await p.context().setOffline(true);
      const url = p.url(); await btn.click();
      await p.waitForTimeout(300);
      r.at300ms = { button: await btn.evaluate((b) => `${b.innerText.trim()}${b.disabled ? ' [disabled]' : ''}`).catch(() => 'gone') };
      if (setup.doubleClick) await btn.click({ force: true, timeout: 800 }).catch(() => {});
      await p.waitForTimeout(setup.wait || 2000);
      if (setup.offline) await p.context().setOffline(false);
      Object.assign(r, { url: p.url() === url ? 'same' : p.url().replace(BASE, ''), messages: await visible(p), focus: await focus(p), writes });
    } catch (e) { r.err = String(e).slice(0, 160); }
    await p.close({ runBeforeUnload: false });
    return r;
  };

  const out = {};
  out.success = await run('ok', {});
  out.error500 = await run('500', { onWrite: (rt) => rt.fulfill({ status: 500, contentType: 'application/json', body: '{"error":"simulated"}' }) });
  out.offline = await run('offline', { offline: true });
  out.slowDoubleClick = await run('slow', { doubleClick: true, wait: 4000, onWrite: async (rt) => { await new Promise((res) => setTimeout(res, 2500)); return rt.continue(); } });
  return JSON.stringify(out, null, 1);
}
