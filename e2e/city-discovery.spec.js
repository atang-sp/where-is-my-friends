/* eslint-disable qunit/require-expect */
import { expect, test } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";

const PLUGIN_PATH = "/where-is-my-friends";

async function authenticate(context, username) {
  const state = JSON.parse(
    await fs.readFile(
      path.join(import.meta.dirname, ".auth", `${username}.json`)
    )
  );
  await context.addCookies(state.cookies);
}

async function openDiscovery(context, page, username) {
  await authenticate(context, username);
  await page.goto(PLUGIN_PATH);
  await expect(
    page.getByRole("heading", { name: "Local Friends" })
  ).toBeVisible();
}

test.describe.serial("Local Friends against real Discourse", () => {
  test("administrator can save a masked AI provider from the plugin page", async ({
    context,
    page,
  }) => {
    await authenticate(context, "admin");
    await page.goto("/admin/plugins/where-is-my-friends/ai-providers");

    await expect(
      page.getByRole("heading", { name: "AI providers", exact: true })
    ).toBeVisible();
    await page.getByLabel("Display name").fill("E2E generation gateway");
    await page.getByLabel("Base URL").fill("https://api.openai.com/v1");
    await page.getByLabel("Model").fill("e2e-model");
    await page.getByLabel("API key").fill("browser-secret-must-not-return");
    await page.getByRole("button", { name: "Save" }).click();

    const card = page.locator("[data-provider-id]").filter({
      hasText: "E2E generation gateway",
    });
    await expect(card).toContainText("e2e-model");
    await expect(card).toContainText("Configured");
    await expect(page.getByLabel("API key")).toHaveValue("");
  });

  test("interest onboarding introduces visible topics and opted-in contributors", async ({
    context,
    page,
  }) => {
    await authenticate(context, "admin");
    await page.goto("/latest");

    await expect(
      page.locator("[data-test-interest-onboarding-callout]")
    ).toBeVisible();
    await page.locator("[data-test-open-interest-onboarding]").click();
    await expect(page).toHaveURL("/where-is-my-friends/interests");

    await expect(
      page.locator("[data-test-public-interests]")
    ).not.toBeChecked();
    await expect(page.locator("[data-test-recommendable]")).toBeChecked();
    await page.locator("[data-test-interest='ruby']").click();
    await page.locator("[data-test-interest='design']").click();
    await page.locator("[data-test-interest='community']").click();
    await page.locator("[data-test-purpose='learn']").click();
    await page.locator("[data-test-save-interests]").click();

    const topic = page
      .locator("[data-test-recommended-topic]")
      .filter({ hasText: "Practical Ruby patterns for community projects" });
    await expect(topic).toContainText(
      "Practical Ruby patterns for community projects"
    );
    await expect(topic).toContainText("ruby");
    await expect(
      page.locator("[data-test-recommended-user='shanghai_one']")
    ).toContainText("Shanghai One");
  });

  test("homepage recommendations stay compact and render one group at a time", async ({
    context,
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await authenticate(context, "admin");
    let recommendationRequests = 0;
    page.on("request", (request) => {
      if (request.url().includes("/recommendations.json")) {
        recommendationRequests += 1;
      }
    });

    await page.goto("/latest");

    const panel = page.locator("[data-test-community-discovery]");
    await expect(panel).toBeVisible();
    await expect(page.locator("[data-test-community-content]")).toHaveCount(0);
    await expect(page.locator("[data-test-local-friends-callout]")).toHaveCount(
      0
    );
    await expect(page.locator(".topic-list-item").first()).toBeVisible();
    expect(recommendationRequests).toBe(0);
    expect((await panel.boundingBox()).height).toBeLessThanOrEqual(64);

    const toggle = page.locator("[data-test-community-toggle]");
    await expect(toggle).toHaveAttribute(
      "aria-controls",
      "community-discovery-content"
    );
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await toggle.focus();
    await expect(toggle).toBeFocused();
    await page.keyboard.press("Enter");

    await expect(page.locator("[data-test-community-content]")).toBeVisible();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    await expect(
      page.locator("[data-test-community-topic]").first()
    ).toBeVisible();
    await expect(page.locator("[data-test-community-person]")).toHaveCount(0);
    expect(recommendationRequests).toBe(1);

    await page.locator("[data-test-community-group='people']").click();
    await expect(page.locator("[data-test-community-topic]")).toHaveCount(0);
    await expect(
      page.locator("[data-test-community-person='shanghai_one']")
    ).toBeVisible();
    await expect(
      page.locator("[data-test-community-person-primary-action]")
    ).toBeVisible();

    const recommendedPerson = page.locator(
      "[data-test-community-person='shanghai_one']"
    );
    await recommendedPerson.locator("[data-test-community-dismiss]").click();
    await expect(recommendedPerson).toHaveCount(0);
    await expect(page.locator("[data-test-community-empty]")).toBeVisible();

    await page.setViewportSize({ width: 390, height: 844 });
    await expect(panel).toBeVisible();
    await expect(page.locator("[data-test-local-friends-callout]")).toHaveCount(
      0
    );
    const sizes = await page.evaluate(() => ({
      viewport: window.innerWidth,
      content: document.documentElement.scrollWidth,
    }));
    expect(sizes.content).toBeLessThanOrEqual(sizes.viewport);
  });

  test("topic lists expose the privacy-safe local discovery entry", async ({
    context,
    page,
  }) => {
    await authenticate(context, "city_entry");
    await page.goto("/latest");

    const callout = page.locator("[data-test-local-friends-callout]");
    await expect(callout).toBeVisible();
    await expect(
      page.locator("[data-test-local-friends-callout-proof]")
    ).toHaveText("3 people have joined — are any near you?");
    await expect(
      page.locator("[data-test-callout-city-card='上海']")
    ).toBeVisible();
    await expect(
      page.locator("[data-test-local-friends-callout-setup]")
    ).toHaveCount(0);
    await page
      .getByRole("link", { name: "Local Friends", exact: true })
      .click();

    await expect(page).toHaveURL(PLUGIN_PATH);
    await expect(page.locator("[data-test-participant-proof]")).toHaveText(
      "3 members across 2 cities have joined local discovery"
    );
    await expect(
      page.locator("[data-test-city-directory-active]")
    ).toBeVisible();
    const citySuggestions = page.locator(
      "#where-is-my-friends-city-suggestions option"
    );
    expect(await citySuggestions.count()).toBeGreaterThan(2);
    await expect(
      page.locator("#where-is-my-friends-city-suggestions option[value='上海']")
    ).toHaveCount(1);
    await expect(
      page.locator("#where-is-my-friends-city-suggestions option[value='杭州']")
    ).toHaveCount(1);
    await expect(page.locator("[data-test-region-field]")).toHaveCount(0);
    await page.locator("[data-test-toggle-region]").click();
    await expect(page.locator("[data-test-region-field]")).toBeVisible();
  });

  test("city-only onboarding automatically shows same-city members", async ({
    context,
    page,
  }) => {
    await openDiscovery(context, page, "admin");
    await page.locator("[data-test-city-input]").fill("上海");
    await page.locator("[data-test-preview-city]").click();
    await expect(page.locator("[data-test-local-topic]")).toHaveCount(0);
    await expect(
      page.locator("[data-test-city-network-preview] [data-test-local-topics]")
    ).toHaveAttribute(
      "href",
      /^\/new-topic\?category_id=\d+&tags=%E4%B8%AD%E5%9B%BD,%E4%B8%8A%E6%B5%B7$/
    );
    await expect(page.locator("[data-test-join-notify-city]")).toBeChecked();
    await expect(page.locator("[data-test-join-notify-nearby]")).toBeChecked();
    await page.locator("[data-test-join-city]").click();

    await expect(
      page.locator("[data-test-user-card='shanghai_one']")
    ).toBeVisible();
    await expect(
      page.locator("[data-test-user-card='shanghai_two']")
    ).toBeVisible();
    await expect(page.locator("[data-test-find-nearby]")).toHaveCount(0);
  });

  test("a cold city expands to nearby regional members", async ({
    context,
    page,
  }) => {
    await openDiscovery(context, page, "empty_city");
    await expect(page.locator("[data-test-expanded-radius]")).toHaveText(
      "No members within 100 km — expanded to 200 km"
    );
    await expect(page.locator("[data-test-results-summary]")).toHaveText(
      "3 members within 200 km of 杭州"
    );
    await expect(page.locator("[data-test-city-group='上海']")).toBeVisible();
    await expect(page.locator("[data-test-user-card]")).toHaveCount(3);
    const localTopics = page.locator("[data-test-local-topics]");
    await expect(localTopics).toHaveAttribute(
      "href",
      "/search?q=%E6%9D%AD%E5%B7%9E"
    );
    await expect(page.locator("[data-test-local-topic]")).toHaveCount(0);
    const contentOrder = await page
      .locator("[data-test-user-card], [data-test-local-topics]")
      .evaluateAll((elements) =>
        elements.map((element) =>
          element.hasAttribute("data-test-user-card") ? "member" : "topics"
        )
      );
    expect(contentOrder[contentOrder.length - 1]).toBe("topics");
  });

  test("profile and secondary connection actions work", async ({
    context,
    page,
  }) => {
    await openDiscovery(context, page, "shanghai_one");
    const profile = page.locator("[data-test-profile-link='shanghai_two']");
    const message = page.locator("[data-test-message-link='shanghai_two']");

    await expect(page.locator("[data-test-results-summary]")).toHaveText(
      "2 members within 100 km of 上海"
    );
    const localTopics = page.locator("[data-test-local-topics]");
    await expect(localTopics).toHaveAttribute(
      "href",
      "/search?q=%E4%B8%8A%E6%B5%B7"
    );
    await expect(page.locator("[data-test-local-topic]")).toHaveCount(0);
    await expect(
      page.getByRole("heading", { name: "Local Friends" })
    ).toBeVisible();
    await expect(page.locator("[data-test-safety-tip]")).toBeVisible();
    const locationSettings = page.locator("[data-test-location-settings]");
    await expect(locationSettings).not.toHaveAttribute("open", "");
    await page.locator("[data-test-location-settings-toggle]").click();
    await expect(locationSettings).toHaveAttribute("open", "");
    await expect(profile).toHaveAttribute("href", "/u/shanghai_two");
    await expect(message).toHaveAttribute(
      "href",
      /^\/(?:new-message\?username=shanghai_two|chat\/new-message\?recipients=shanghai_two)$/
    );
    await profile.click();
    await expect(page).toHaveURL(/\/u\/shanghai_two/);

    await page.goto(PLUGIN_PATH);
    await page.locator("[data-test-message-link='shanghai_two']").click();
    if (page.url().includes("/chat/")) {
      await expect(page.locator(".chat-composer__input")).toBeVisible();
    } else {
      await expect(page.locator(".composer-fields")).toBeVisible();
      await page.locator(".toggle-save-and-close").click();
      await expect(page.locator("#reply-control")).toHaveClass(/closed/);
    }
  });

  test("GPS denial immediately preserves city discovery", async ({
    context,
    page,
  }) => {
    await context.clearPermissions();
    await openDiscovery(context, page, "shanghai_one");
    await page.locator("[data-test-location-settings-toggle]").click();
    await page.locator("[data-test-advanced-location]").click();
    await page.locator("[data-test-use-gps]").click();

    await expect(page.locator("[data-test-gps-fallback]")).toBeVisible();
    await expect(
      page.locator("[data-test-location-mode='city']")
    ).toBeVisible();
  });

  test("map selection upgrades the stored mode", async ({ context, page }) => {
    await openDiscovery(context, page, "shanghai_two");
    await page.locator("[data-test-location-settings-toggle]").click();
    await page.locator("[data-test-advanced-location]").click();
    await page.locator("[data-test-use-map]").click();
    await expect(page.locator("[data-test-map-provider]")).toHaveText(
      "OpenStreetMap"
    );
    await page.locator("[data-test-map-latitude]").fill("31.2304");
    await page.locator("[data-test-map-longitude]").fill("121.4737");
    await page.locator("[data-test-confirm-map]").click();

    await expect(page.locator("[data-test-location-mode='map']")).toBeVisible();
    await expect(page.locator("[data-test-precise-coordinates]")).toHaveCount(
      0
    );
  });

  test("a member can remove their discovery location", async ({
    context,
    page,
  }) => {
    await openDiscovery(context, page, "empty_city");
    await page.locator("[data-test-location-settings-toggle]").click();
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
    await expect(cards.first()).toBeVisible();
    const cardCount = await cards.count();
    const first = await cards.nth(0).boundingBox();
    if (cardCount > 1) {
      const second = await cards.nth(1).boundingBox();
      expect(second.y).toBeGreaterThan(first.y);
    }
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
    expect(
      report.funnel.recommendation_groups.topics.exposed_users
    ).toBeGreaterThan(0);
    expect(report.funnel.local_callout.viewed_users).toBeGreaterThan(0);
    expect(report.funnel.mature_cohorts).toHaveProperty(
      "recommendation_exposure"
    );
    expect(report.content_supply).toHaveProperty("public_topics_created");
    expect(report.daily.length).toBeGreaterThan(0);
    expect(report.period).toHaveProperty("starts_at");
    expect(report).not.toHaveProperty("latitude");
    expect(report).not.toHaveProperty("longitude");
  });
});
