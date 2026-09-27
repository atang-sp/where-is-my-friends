import { test, expect } from "@playwright/test";

test.describe("Interest Onboarding", () => {
  test("allows navigating to the interest onboarding page", async ({ page }) => {
    await page.goto("/");
    // Navigate to /where-is-my-friends/interests
  });

  test("allows selecting public interests and purpose from the catalogue", async ({ page }) => {
    await page.goto("/where-is-my-friends/interests");
    // Select interests
    // Assert selections are active
  });

  test("allows proceeding through the onboarding flow and saving", async ({ page }) => {
    await page.goto("/where-is-my-friends/interests");
    // Save changes
    // Assert success state
  });
});
