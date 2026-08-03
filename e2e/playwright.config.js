import { defineConfig, devices } from "@playwright/test";

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
const disableBrowserSandbox = ["1", "true"].includes(
  (process.env.DISCOURSE_DISABLE_BROWSER_SANDBOX || "").toLowerCase()
);
const launchOptions = {
  ...(executablePath ? { executablePath } : {}),
  ...(disableBrowserSandbox ? { args: ["--no-sandbox"] } : {}),
};

export default defineConfig({
  globalSetup: "./global-setup.cjs",
  testDir: ".",
  testMatch: ["city-discovery.spec.js", "personal-dynamics.spec.js"],
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30_000,
  expect: { timeout: 8_000 },
  use: {
    baseURL: process.env.BASE_URL || "http://127.0.0.1:3000",
    ...(Object.keys(launchOptions).length ? { launchOptions } : {}),
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "mobile-chromium",
      grep: /@mobile/,
      use: { ...devices["Pixel 5"] },
    },
  ],
});
