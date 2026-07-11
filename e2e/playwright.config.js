import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  globalSetup: "./global-setup.cjs",
  testDir: ".",
  testMatch: "city-discovery.spec.js",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30_000,
  expect: { timeout: 8_000 },
  use: {
    baseURL: process.env.BASE_URL || "http://127.0.0.1:3000",
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
