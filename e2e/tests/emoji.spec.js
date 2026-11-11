// Card « Messages : bouton emoji inutile sur téléphone » (validated on
// 5 Nov 2026, 17 h 14): the phone keyboard has its own emojis, so the
// emoji button of the input bar is only shown on computers (and Tesla).
// The web client decides by the platform the browser reports: a computer
// browser keeps the button, an iPhone browser has none.
const { test, expect, request: apiRequest } = require('@playwright/test');
const { createEvent, joinEvent } = require('./helpers');

const RUN = `${Date.now()}`.slice(-6);
const EVENT_NAME = `E2E emoji ${RUN}`;

// Flutter web takes the system from navigator.platform (« iPhone » in
// Safari on an iPhone), not from the user agent: both are set.
const IPHONE = {
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
};

// « Messages » or « Messages 1 » once the unread badge is shown.
const messagesTab = (page) => page.getByRole('button', { name: /^Messages(\s+\d+)?$/ });

test.describe.serial('emoji button of the input bar', () => {
  let api;

  test.beforeAll(async ({ baseURL }) => {
    api = await apiRequest.newContext({ baseURL });
    // No message: the conversations are listed anyway (an unread badge
    // would change the accessible name of « Messages » while joining).
    await createEvent(api, EVENT_NAME);
  });

  test.afterAll(async () => { await api?.dispose(); });

  test('computer: the emoji button is there', async ({ browser, baseURL }) => {
    const context = await browser.newContext({ baseURL, locale: 'en-US', viewport: { width: 1280, height: 900 } });
    const page = await context.newPage();
    try {
      await joinEvent(page, { eventName: EVENT_NAME, deviceId: 'PC-EMOJI' });
      // Computer: « Messages » opens (or closes) the panel, on « Everyone ».
      const field = page.getByLabel('Message', { exact: true });
      await expect(async () => {
        if (!(await field.isVisible())) await messagesTab(page).click();
        await expect(field).toBeVisible({ timeout: 5_000 });
      }).toPass({ timeout: 60_000 });
      await expect(page.getByRole('button', { name: 'Emojis', exact: true })).toBeVisible();
    } finally { await context.close(); }
  });

  test('iPhone: no emoji button, the keyboard has its own', async ({ browser, baseURL }) => {
    // Joined first in a computer browser, the same way as the other tests
    // (helpers.js, mouse clicks); its settings (local storage and IndexedDB)
    // are then given to the iPhone browser, which only gets touches.
    const setup = await browser.newContext({ baseURL, locale: 'en-US', viewport: { width: 1280, height: 900 } });
    const first = await setup.newPage();
    await joinEvent(first, { eventName: EVENT_NAME, deviceId: 'TEL-EMOJI' });
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
      // Accessibility switched on by a touch: on a phone, Flutter web ignores
      // the click that enableSemantics() sends.
      await page.locator('flt-semantics-placeholder').tap({ force: true, timeout: 60_000 });
      await page.waitForSelector('flt-semantics', { state: 'attached' });
      // Phone: the list first, then the conversation to everyone (the
      // server names its group « Tous », whatever the language).
      const everyone = page.getByRole('button', { name: /^(Tous|Everyone)(\s|$)/ }).first();
      await expect(async () => {
        if (!(await everyone.isVisible())) await messagesTab(page).tap();
        await expect(everyone).toBeVisible({ timeout: 5_000 });
      }).toPass({ timeout: 60_000 });
      await everyone.tap();
      const field = page.getByLabel('Message', { exact: true });
      await expect(field).toBeVisible();
      // The bar is built: the « + » menu is there, the emoji button is not.
      await expect(page.getByRole('button', { name: 'Predefined messages, photo and priority' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Emojis', exact: true })).toHaveCount(0);
    } finally { await context.close(); }
  });
});
