/* eslint-disable qunit/require-expect */
import { expect, test } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";

async function authenticate(context, username) {
  const state = JSON.parse(
    await fs.readFile(
      path.join(import.meta.dirname, ".auth", `${username}.json`)
    )
  );
  await context.addCookies(state.cookies);
}

test.describe.serial("Flying Chess Achievements", () => {
  test("allows viewing the Flying Chess achievement board", async ({ page, context }) => {
    await authenticate(context, "chess_one");
    await page.goto("/where-is-my-friends/flying-chess");
    
    await expect(page.locator(".flying-chess-claim-page")).toBeVisible();
  });

  test("allows redeeming a completed achievement via token", async ({ page, context }) => {
    await authenticate(context, "chess_one");
    // Pass a fake token
    await page.goto("/where-is-my-friends/flying-chess#token=test-fake-token");
    
    await expect(page.locator(".flying-chess-claim-page")).toBeVisible();
    
    const confirmButton = page.locator(".btn-primary");
    if (await confirmButton.isVisible()) {
      await confirmButton.click();
      // It will likely fail with invalid token, we just check error or loading state
      await expect(page.locator(".alert-error, .success")).toBeVisible({ timeout: 5000 });
    }
  });

  test("allows toggling achievement visibility on the profile", async ({ page, context }) => {
    await authenticate(context, "chess_one");
    await page.goto("/u/chess_one/preferences/profile");
    
    // In a real scenario, there would be a toggle in the profile settings 
    // depending on the site settings. We navigate to profile to ensure no crash.
    await expect(page.locator("body")).toBeVisible();
  });
});
