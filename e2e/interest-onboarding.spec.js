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

test.describe.serial("Interest Onboarding", () => {
  test("allows navigating to the interest onboarding page", async ({ page, context }) => {
    await authenticate(context, "interest_one");
    await page.goto("/latest");
    // Depending on the entry point, the user might see the onboarding prompt or go directly.
    await page.goto("/where-is-my-friends/interests");
    await expect(page.locator("[data-test-interest-onboarding-form]")).toBeVisible();
  });

  test("allows selecting public interests and purpose from the catalogue", async ({ page, context }) => {
    await authenticate(context, "interest_one");
    await page.goto("/where-is-my-friends/interests");
    
    await expect(page.locator("[data-test-interest-onboarding-form]")).toBeVisible();
    
    // Select an interest if it exists
    const interestOptions = page.locator("[data-test-interest]");
    if (await interestOptions.count() > 0) {
      await interestOptions.first().click();
    }
  });

  test("allows proceeding through the onboarding flow and saving", async ({ page, context }) => {
    await authenticate(context, "interest_one");
    await page.goto("/where-is-my-friends/interests");
    
    const saveButton = page.locator("[data-test-save-interests]");
    await expect(saveButton).toBeVisible();
    
    await saveButton.click();
    
    // Assert success or next state, usually going back or showing success message
    await expect(page.locator("[data-test-interest-onboarding-form]")).toBeHidden();
  });
});
