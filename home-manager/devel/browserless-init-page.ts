// Browserless renders pages at 800x600 and ignores Playwright's viewport
// emulation, which flips responsive sites into their mobile layout.
// It also defaults to "HeadlessChrome" in the User-Agent, which is readily
// blocked by bot filters. Here we override both: restoring a desktop viewport
// and masquerading as regular Chrome/Chromium on Linux with client hints.
export default async ({ page }) => {
  const session = await page.context().newCDPSession(page);

  // Restore desktop viewport
  await session.send('Emulation.setDeviceMetricsOverride', {
    width: 1600,
    height: 1000,
    deviceScaleFactor: 1,
    mobile: false,
  });

  // Replace HeadlessChrome with Chrome in User-Agent & set client hints
  try {
    const version = await session.send('Browser.getVersion');
    const normalUserAgent = version.userAgent.replace('HeadlessChrome', 'Chrome');
    const match = version.product.match(/Chrome\/(\d+)/);
    const majorVersion = match ? match[1] : '153';

    await session.send('Network.setUserAgentOverride', {
      userAgent: normalUserAgent,
      platform: 'Linux x86_64',
      userAgentMetadata: {
        brands: [
          { brand: 'Chromium', version: majorVersion },
          { brand: 'Google Chrome', version: majorVersion },
          { brand: 'Not(A:Brand', version: '24' },
        ],
        fullVersion: version.product.replace('Chrome/', ''),
        platform: 'Linux',
        platformVersion: '',
        architecture: 'x86',
        model: '',
        mobile: false,
      },
    });
  } catch (err) {
    console.error('Failed to set User-Agent override via CDP:', err);
  }
};
