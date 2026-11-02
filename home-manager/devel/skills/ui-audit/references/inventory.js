// UI inventory for browser_run_code_unsafe. Edit BASE, ROUTES and VIEWPORTS,
// then pass the whole file as `code`. Read-only: it only navigates and reads.
async (page) => {
  const BASE = 'https://example.com';
  const ROUTES = ['/app/projects', '/app/projects/1', '/app/projects/1/edit'];
  const VIEWPORTS = [[1440, 900], [390, 844]];
  // Elements inside these are app chrome (nav rail, header), not page content.
  const CHROME = '.desktop-rail, nav, header';

  const out = { sigs: {}, pages: {} };
  for (const [w, h] of VIEWPORTS) {
    await page.setViewportSize({ width: w, height: h });
    for (const url of ROUTES) {
      await page.goto(BASE + url);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(800);
      const r = await page.evaluate((chrome) => {
        const vis = (e) => {
          const b = e.getBoundingClientRect(); const s = getComputedStyle(e);
          return b.width > 0 && b.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
        };
        const cls = (e) => [...e.classList].filter((c) => !/^(svelte|css|jsx|sc)-/.test(c)).slice(0, 3).join('.');
        const label = (e) => (e.innerText || e.getAttribute('aria-label') || e.title || e.value || '').trim().replace(/\s+/g, ' ').slice(0, 28);
        const btns = [...document.querySelectorAll('button, a[class*="btn"], a[class*="button"], a[class*="action"], [role="button"], input[type=submit], input[type=button]')]
          .filter(vis).filter((e) => !e.closest(chrome));
        const rows = btns.map((e) => {
          const s = getComputedStyle(e); const b = e.getBoundingClientRect();
          return {
            t: label(e),
            c: e.tagName.toLowerCase() + '.' + cls(e),
            sig: [s.backgroundColor, s.color, s.borderTopWidth + ' ' + s.borderTopColor, s.borderRadius,
              Math.round(b.height) + 'h', s.fontSize, s.fontWeight, s.paddingLeft].join(' | '),
            x: Math.round(b.x), y: Math.round(b.y + scrollY), w: Math.round(b.width), h: Math.round(b.height),
            ico: !!e.querySelector('svg'),
          };
        });
        const h1 = document.querySelector('h1'); const hb = h1 && h1.getBoundingClientRect();
        const main = document.querySelector('main') || document.body;
        return {
          rows,
          h1: h1 ? { t: h1.innerText.trim().slice(0, 30), x: Math.round(hb.x), y: Math.round(hb.y + scrollY), fs: getComputedStyle(h1).fontSize } : null,
          headings: [...document.querySelectorAll('h1,h2,h3')].filter(vis).slice(0, 12)
            .map((e) => e.tagName + ':' + getComputedStyle(e).fontSize + ':' + e.innerText.trim().slice(0, 24)),
          overflow: document.documentElement.scrollWidth - innerWidth,
          offscreen: [...main.querySelectorAll('*')].filter(vis).filter((e) => e.getBoundingClientRect().right > innerWidth + 1)
            .slice(0, 5).map((e) => e.tagName + '.' + cls(e)),
          radii: [...new Set([...main.querySelectorAll('section, article, fieldset, form, [class*="card"]')].filter(vis)
            .map((e) => getComputedStyle(e).borderRadius))],
          inputs: [...new Set([...main.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=hidden]), select, textarea')].filter(vis)
            .map((e) => { const s = getComputedStyle(e); return Math.round(e.getBoundingClientRect().height) + 'h ' + s.borderRadius + ' ' + s.fontSize + ' ' + s.fontFamily.split(',')[0]; }))],
          contentW: [...main.querySelectorAll(':scope > *, :scope > * > *')].filter(vis).slice(0, 3).map((e) => Math.round(e.getBoundingClientRect().width)),
        };
      }, CHROME);
      out.pages[w + ' ' + url] = {
        h1: r.h1, headings: r.headings, overflow: r.overflow, offscreen: r.offscreen, radii: r.radii, inputs: r.inputs, contentW: r.contentW,
        tall: r.rows.filter((b) => b.h > 52).map((b) => `${b.t} ${b.w}x${b.h}`),
        small: w < 500 ? r.rows.filter((b) => b.h < 40 || b.w < 40).map((b) => `${b.t} ${b.w}x${b.h}`) : undefined,
        buttons: r.rows.map((b) => `${b.t}${b.ico ? '*' : ''} [${b.c}] @${b.x},${b.y} ${b.w}x${b.h}`),
      };
      for (const b of r.rows) (out.sigs[b.sig] ||= []).push(`${w}${url}:${b.t}`);
    }
  }
  return JSON.stringify(out);
}
