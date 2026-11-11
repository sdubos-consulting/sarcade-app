// Card « Menu du bas toujours visible (outils et Paramètres compris) »,
// validated on 8 Nov 2026: on a phone, a tool opens inside the Outils tab
// and Paramètres is a tab; the bottom bar stays visible in both.
const { test, expect, request: apiRequest } = require('@playwright/test');
const { createEvent, joinEvent } = require('./helpers');

const RUN = `${Date.now()}`.slice(-6);
const EVENT_NAME = `E2E menu bas ${RUN}`;

// Same iPhone as emoji.spec.js (navigator.platform drives Flutter web).
const IPHONE = {
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
};

const tab = (page, name) => page.getByRole('button', { name, exact: true });

test.describe.serial('bottom bar always visible on a phone', () => {
  let api;

  test.beforeAll(async ({ baseURL }) => {
    api = await apiRequest.newContext({ baseURL });
    await createEvent(api, EVENT_NAME);
  });

  test.afterAll(async () => { await api?.dispose(); });

  test('iPhone: Tools › Files, then Settings, keep the bottom bar', async ({ browser, baseURL }) => {
    // Joined in a computer browser, then the settings given to the iPhone
    // browser (same way as emoji.spec.js).
    const setup = await browser.newContext({ baseURL, locale: 'en-US', viewport: { width: 1280, height: 900 } });
    const first = await setup.newPage();
    await joinEvent(first, { eventName: EVENT_NAME, deviceId: 'TEL-MENU' });
    const storageState = await setup.storageState({ indexedDB: true });
    await setup.close();

    const context = await browser.newContext({ baseURL, locale: 'en-US', ...IPHONE, storageState });
    await context.addInitScript(() => {
      Object.defineProperty(Navigator.prototype, 'platform', { get: () => 'iPhone' });
      Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 5 });
    });
    const page = await context.newPage();
    try {
      await page.goto('/');
      await page.locator('flt-semantics-placeholder').tap({ force: true, timeout: 60_000 });
      await page.waitForSelector('flt-semantics', { state: 'attached' });
      await expect(tab(page, 'Tools')).toBeVisible({ timeout: 60_000 });

      // Outils › Fichiers: the tool is shown, the bar is still there.
      await tab(page, 'Tools').tap();
      const files = page.getByRole('button', { name: /^Files\b/ }).first();
      await expect(files).toBeVisible();
      await files.tap();
      await expect(page.getByRole('button', { name: /^Back$/ })).toBeVisible();
      await expect(tab(page, 'Map')).toBeVisible();
      await expect(tab(page, 'Settings')).toBeVisible();

      // Outils touched again: back to the list of the tools.
      await tab(page, 'Tools').tap();
      await expect(page.getByRole('button', { name: /^Back$/ })).toHaveCount(0);
      await expect(files).toBeVisible();

      // Paramètres: its list is shown (no tabs since 9 Nov 2026), the bar is still there.
      await tab(page, 'Settings').tap();
      await expect(page.getByRole('button', { name: /This device/ })).toBeVisible();
      await expect(tab(page, 'Map')).toBeVisible();
      await expect(tab(page, 'Tools')).toBeVisible();

      // Carte: the map again.
      await tab(page, 'Map').tap();
      await expect(page.getByRole('button', { name: /This device/ })).toHaveCount(0);
    } finally { await context.close(); }
  });
});
