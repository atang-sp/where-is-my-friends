const fs = require("node:fs/promises");
const path = require("node:path");
const { chromium, expect } = require("@playwright/test");

const PASSWORD = "LocalFriendsTest123!";
const USERS = ["admin", "shanghai_one", "shanghai_two", "empty_city"];

module.exports = async function globalSetup(config) {
  const baseURL = config.projects[0].use.baseURL;
  const authDirectory = path.join(__dirname, ".auth");
  await fs.mkdir(authDirectory, { recursive: true });
  const browser = await chromium.launch();

  try {
    for (const username of USERS) {
      const context = await browser.newContext({ baseURL });
      const page = await context.newPage();
      await page.goto("/login");
      await page.locator("#login-account-name").fill(username);
      await page.locator("#login-account-password").fill(PASSWORD);
      await page.locator("#login-button").click();
      await expect(page.locator(".login-fullpage")).toBeHidden();
      await context.storageState({
        path: path.join(authDirectory, `${username}.json`),
      });
      await context.close();
    }
  } finally {
    await browser.close();
  }
};
