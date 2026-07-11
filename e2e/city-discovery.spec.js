/* eslint-disable qunit/require-expect */
import { expect, test } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";

const PLUGIN_PATH = "/where-is-my-friends";

async function authenticate(context, username) {
  const state = JSON.parse(
    await fs.readFile(path.join(import.meta.dirname, ".auth", `${username}.json`))
  );
  await context.addCookies(state.cookies);
}

async function openDiscovery(context, page, username) {
  await authenticate(context, username);
  await page.goto(PLUGIN_PATH);
  await expect(page.getByRole("heading", { name: "Local Friends" })).toBeVisible();
}

test.describe.serial("Local Friends against real Discourse", () => {
  test("city-only onboarding automatically shows same-city members", async ({
    context,
    page,
  }) => {
    await openDiscovery(context, page, "admin");
    await page.locator("[data-test-city-input]").fill("上海");
    await page.locator("[data-test-save-city]").click();

    await expect(
      page.locator("[data-test-user-card='shanghai_one']")
    ).toBeVisible();
    await expect(
      page.locator("[data-test-user-card='shanghai_two']")
    ).toBeVisible();
    await expect(page.locator("[data-test-find-nearby]")).toHaveCount(0);
  });

  test("an empty city offers a local topic path", async ({ context, page }) => {
    await openDiscovery(context, page, "empty_city");
    await expect(page.locator("[data-test-empty-state]")).toBeVisible();
    const localTopics = page.locator("[data-test-local-topics]");
    await expect(localTopics).toHaveAttribute("href", /\/search\?q=/);
    await localTopics.click();
    await expect(page).toHaveURL(/\/search\?q=/);
  });

  test("profile and private-message actions work", async ({ context, page }) => {
    await openDiscovery(context, page, "shanghai_one");
    const profile = page.locator("[data-test-profile-link='shanghai_two']");
    const message = page.locator("[data-test-message-link='shanghai_two']");

    await expect(profile).toHaveAttribute("href", "/u/shanghai_two");
    await expect(message).toHaveAttribute(
      "href",
      "/new-message?username=shanghai_two"
    );
    await profile.click();
    await expect(page).toHaveURL(/\/u\/shanghai_two/);

    await page.goto(PLUGIN_PATH);
    await page.locator("[data-test-message-link='shanghai_two']").click();
    await expect(page.locator(".composer-fields")).toBeVisible();
  });

  test("GPS denial immediately preserves city discovery", async ({
    context,
    page,
  }) => {
    await context.clearPermissions();
    await openDiscovery(context, page, "shanghai_one");
    await page.locator("[data-test-advanced-location]").click();
    await page.locator("[data-test-use-gps]").click();

    await expect(page.locator("[data-test-gps-fallback]")).toBeVisible();
    await expect(page.locator("[data-test-location-mode='city']")).toBeVisible();
  });

  test("map selection upgrades the stored mode", async ({ context, page }) => {
    await openDiscovery(context, page, "shanghai_two");
    await page.locator("[data-test-advanced-location]").click();
    await page.locator("[data-test-use-map]").click();
    await expect(page.locator("[data-test-map-provider]")).toHaveText(
      "OpenStreetMap"
    );
    await page.locator("[data-test-map-latitude]").fill("31.2304");
    await page.locator("[data-test-map-longitude]").fill("121.4737");
    await page.locator("[data-test-confirm-map]").click();

    await expect(page.locator("[data-test-location-mode='map']")).toBeVisible();
    await expect(page.locator("[data-test-precise-coordinates]")).toHaveCount(0);
  });

  test("a member can remove their discovery location", async ({ context, page }) => {
    await openDiscovery(context, page, "empty_city");
    await page.locator("[data-test-remove-location]").click();

    await expect(page.locator("[data-test-city-input]")).toBeVisible();
    await expect(page.locator("[data-test-location-mode]")).toHaveCount(0);
  });

  test("@mobile layout stays single-column without horizontal overflow", async ({
    context,
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await openDiscovery(context, page, "shanghai_one");
    const cards = page.locator("[data-test-user-card]");
    await expect(cards).toHaveCount(2);
    const first = await cards.nth(0).boundingBox();
    const second = await cards.nth(1).boundingBox();
    expect(second.y).toBeGreaterThan(first.y);
    const sizes = await page.evaluate(() => ({
      viewport: window.innerWidth,
      content: document.documentElement.scrollWidth,
    }));
    expect(sizes.content).toBeLessThanOrEqual(sizes.viewport);
  });

  test("admin can read aggregate funnel metrics", async ({ context, page }) => {
    await authenticate(context, "admin");
    const response = await page.request.get(
      "/where-is-my-friends/debug-stats.json"
    );

    expect(response.ok()).toBeTruthy();
    const report = await response.json();
    expect(report.funnel.unique_page_visitors).toBeGreaterThan(0);
    expect(report).not.toHaveProperty("latitude");
    expect(report).not.toHaveProperty("longitude");
  });
});
