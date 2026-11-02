// Layout shift, hover and focus check for browser_run_code_unsafe. Edit BASE
// and ROUTES, then pass the whole file as `code`. Read-only: it hovers and
// presses Tab, it never clicks.
async (page) => {
  const BASE = 'https://example.com';
  const ROUTES = ['/app/projects', '/app/projects/1'];
  const MAX_HOVER = 14; // buttons hovered per page
  const TABS = 25; // Tab presses per page; enough to get past the nav

  await page.setViewportSize({ width: 1440, height: 900 });
  // Init scripts persist for the browser's lifetime: a second run in the same
  // session would register a second observer and double every entry.
  await page.addInitScript(() => {
    if (window.__ls) return;
    window.__ls = [];
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        if (e.hadRecentInput) continue;
        window.__ls.push({
          v: +e.value.toFixed(4), t: Math.round(e.startTime),
          // [prevY, curY, prevX, curX] per moved element
          src: (e.sources || []).map((s) => {
            const n = s.node; if (!n || !n.tagName) return '?';
            const c = [...n.classList].filter((x) => !/^(svelte|css|jsx|sc)-/.test(x)).slice(0, 2).join('.');
            return n.tagName.toLowerCase() + '.' + c + ' ' + JSON.stringify([s.previousRect.y, s.currentRect.y, s.previousRect.x, s.currentRect.x].map(Math.round));
          }),
        });
      }
    }).observe({ type: 'layout-shift', buffered: true });
  });

  const PROPS = ['color', 'background-color', 'background-image', 'border-color', 'border-top-width', 'box-shadow',
    'filter', 'opacity', 'transform', 'text-decoration-line', 'outline-style'];
  const out = {};
  for (const url of ROUTES) {
    await page.goto(BASE + url);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1500);
    const shifts = await page.evaluate(() => window.__ls);

    const hover = [];
    for (const h of (await page.$$('main button, main a[class*="button"], main a[class*="btn"], main a[class*="action"]')).slice(0, MAX_HOVER)) {
      try {
        if (!(await h.isVisible())) continue;
        await h.scrollIntoViewIfNeeded();
        const snap = () => h.evaluate((e, props) => {
          const s = getComputedStyle(e); const b = e.getBoundingClientRect();
          return { t: (e.innerText || e.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ').slice(0, 20), y: b.y, w: b.width, h: b.height, css: props.map((p) => s.getPropertyValue(p)) };
        }, PROPS);
        const a = await snap(); await h.hover(); await page.waitForTimeout(350); const b = await snap();
        const d = PROPS.filter((_, i) => a.css[i] !== b.css[i]);
        if (Math.abs(b.y - a.y) > 0.5) d.push('moves ' + (b.y - a.y).toFixed(1) + 'px');
        if (Math.abs(b.w - a.w) > 0.5 || Math.abs(b.h - a.h) > 0.5) d.push('resizes');
        hover.push(a.t + ': ' + (d.length ? d.join(', ') : 'NO hover feedback'));
      } catch (e) { /* detached or hidden after hover */ }
    }
    await page.mouse.move(0, 0);

    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    const focus = [];
    for (let i = 0; i < TABS; i++) {
      await page.keyboard.press('Tab');
      const f = await page.evaluate(() => {
        const e = document.activeElement; if (!e || e === document.body) return null;
        const s = getComputedStyle(e);
        const ring = s.outlineStyle !== 'none' && s.outlineWidth !== '0px' ? 'outline ' + s.outlineWidth : (s.boxShadow !== 'none' ? 'shadow' : 'NONE');
        return (e.innerText || e.getAttribute('aria-label') || e.tagName).trim().replace(/\s+/g, ' ').slice(0, 18) + ': ' + ring;
      });
      if (f) focus.push(f);
    }

    // Per route: SPAs load route CSS lazily. Recurse into @media, @layer and nested rules.
    const hoverRules = await page.evaluate(() => {
      let n = 0;
      const walk = (rules) => { for (const r of rules) { if (r.selectorText && r.selectorText.includes(':hover')) n++; if (r.cssRules) walk(r.cssRules); } };
      for (const ss of document.styleSheets) { try { walk(ss.cssRules); } catch (e) { /* cross-origin sheet */ } }
      return n;
    });

    out[url] = { cls: +shifts.reduce((s, e) => s + e.v, 0).toFixed(4), shifts: shifts.slice(0, 6), hover, hoverRules, focusMissing: focus.filter((f) => f.endsWith('NONE')), focusSample: focus.slice(-6) };
  }
  return JSON.stringify(out);
}
