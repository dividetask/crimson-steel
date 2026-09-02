import { defineConfig } from '@playwright/test';

// Browser tests — see docs/project/browser_tests.md.
//
// Each test boots its own server against its own throwaway Campaign
// (test/e2e/support/fixtures.mjs), so there is no global webServer here
// and no shared state between tests.
export default defineConfig({
  testDir: './test/e2e',
  testMatch: '**/*.spec.mjs',
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: {
    headless: true,
    // The container ships Chromium at a fixed location and blocks
    // `playwright install`; point the browser at it rather than letting
    // Playwright look for a build it would have to download.
    launchOptions: { executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' },
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
});
