// Density probe for browser_run_code_unsafe: how much chrome, text and how
// many controls come before the first real content item. Edit BASE and ROUTES
// (route + CSS selector of the first content item), then pass the whole file
// as `code`. Read-only: it only navigates.
async (page) => {
  const BASE = 'https://example.com';
  // Point the selector at the content item itself (the card or row), not at
  // text inside it, or the item appears lower than it is.
  const ROUTES = [
    ['/app/projects', 'main a[href^="/app/projects/"]'],
    ['/app/projects/1', 'main article p'],
  ];
  const VIEWPORTS = [[390, 844], [1440, 900]];

  const out = {};
  for (const [w, h] of VIEWPORTS) {
    const p = await page.context().newPage();
    await p.setViewportSize({ width: w, height: h });
    for (const [url, sel] of ROUTES) {
      await p.goto(BASE + url); await p.waitForLoadState('networkidle'); await p.waitForTimeout(500);
      await p.evaluate(() => scrollTo(0, 0));
      out[`${w} ${url}`] = await p.evaluate((sel) => {
        const vis = (e) => { const b = e.getBoundingClientRect(); const s = getComputedStyle(e); return b.width > 0 && b.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0'; };
        // Fixed or sticky bars spanning most of the width count as chrome.
        const bars = [...document.querySelectorAll('body *')].filter((e) => vis(e) && ['fixed', 'sticky'].includes(getComputedStyle(e).position) && e.getBoundingClientRect().width > innerWidth * 0.6);
        const top = bars.filter((e) => e.getBoundingClientRect().y < 5).reduce((m, e) => Math.max(m, e.getBoundingClientRect().bottom), 0);
        const bottom = bars.filter((e) => e.getBoundingClientRect().bottom > innerHeight - 5 && e.getBoundingClientRect().y > innerHeight / 2).reduce((m, e) => Math.max(m, innerHeight - e.getBoundingClientRect().y), 0);
        const fold = innerHeight - bottom;
        const first = [...document.querySelectorAll(sel)].find(vis);
        const firstY = first ? Math.round(first.getBoundingClientRect().y + scrollY) : null;
        const main = document.querySelector('main') || document.body;
        // Itemised list of what sits above the first content item.
        const above = [...main.querySelectorAll('h1,h2,h3,p,label,legend,input,select,textarea,button,a,small,span')]
          .filter(vis).filter((e) => !e.closest('nav'))
          .filter((e) => firstY === null || e.getBoundingClientRect().y + scrollY < firstY - 2)
          .filter((e) => !(e.tagName === 'SPAN' && e.closest('button,a,label,h1,h2,h3,p')))
          .filter((e) => !(['P', 'H1', 'H2', 'H3', 'LABEL'].includes(e.tagName) && e.closest('button,a')))
          .slice(0, 25)
          .map((e) => { const b = e.getBoundingClientRect(); const t = (e.innerText || e.placeholder || e.value || e.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' '); return `${Math.round(b.y + scrollY)}+${Math.round(b.height)} ${e.tagName.toLowerCase()} ${t.slice(0, 40)}`; });
        const controls = [...main.querySelectorAll('button,a[href],input:not([type=hidden]),select,textarea')].filter(vis);
        const words = []; const tw = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
        while (tw.nextNode()) { const n = tw.currentNode; const pe = n.parentElement; if (n.textContent.trim() && vis(pe) && pe.getBoundingClientRect().y < fold) words.push(...n.textContent.trim().split(/\s+/)); }
        return {
          chrome: `${Math.round(top)}px top + ${Math.round(bottom)}px bottom = ${Math.round((top + bottom) / innerHeight * 100)}%`,
          firstContentY: firstY, firstContentAboveFold: firstY !== null && firstY < fold,
          controlsAboveFold: controls.filter((e) => e.getBoundingClientRect().y < fold).length, controlsTotal: controls.length,
          wordsAboveFold: words.length, docHeight: document.documentElement.scrollHeight, above,
        };
      }, sel);
    }
    await p.close();
  }
  return JSON.stringify(out, null, 1);
}
