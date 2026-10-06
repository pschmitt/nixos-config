// Browserless renders pages at 800x600 and ignores Playwright's viewport
// emulation, which flips responsive sites into their mobile layout.
export default async ({ page }) => {
  const session = await page.context().newCDPSession(page);
  await session.send('Emulation.setDeviceMetricsOverride', {
    width: 1600,
    height: 1000,
    deviceScaleFactor: 1,
    mobile: false,
  });
};
