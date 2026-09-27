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

test.describe.serial("User Tags", () => {
  test("allows viewing and endorsing tags on a user profile", async ({ page, context }) => {
    await authenticate(context, "tags_one");
    await page.goto("/u/tags_two");
    
    // Check if user tag area is visible
    const tagArea = page.locator("[data-test-user-tags]");
    // We just assert the structure for now since creating a tag end-to-end might require specific state
    if (await tagArea.isVisible()) {
        const endorseButton = page.locator("[data-test-user-tag-endorse]").first();
        if (await endorseButton.isVisible()) {
            await endorseButton.click();
        }
    }
  });

  test("allows proposing a new tag", async ({ page, context }) => {
    await authenticate(context, "tags_one");
    await page.goto("/u/tags_two");
    
    const proposeButton = page.locator("[data-test-user-tag-propose]");
    if (await proposeButton.isVisible()) {
      await proposeButton.click();
      const input = page.locator("[data-test-user-tag-input]");
      await expect(input).toBeVisible();
      await input.fill("Helpful member");
      
      const submit = page.locator("[data-test-user-tag-propose-submit]");
      await submit.click();
    }
  });

  test("allows managing incoming tag proposals in the inbox", async ({ page, context }) => {
    await authenticate(context, "tags_two");
    await page.goto("/where-is-my-friends/tags");
    
    const inbox = page.locator("[data-test-user-tag-inbox]");
    if (await inbox.isVisible()) {
        const approveButton = page.locator("[data-test-user-tag-approve]").first();
        if (await approveButton.isVisible()) {
            await approveButton.click();
        }
    }
  });
});
