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

test.describe.serial("Personal dynamics against real Discourse", () => {
  let dynamicUrl;

  test("one member publishes a text-only dynamic from their profile entry", async ({
    context,
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await authenticate(context, "dynamics_one");
    await page.goto("/u/dynamics_one");

    const publishEntry = page.locator("[data-test-profile-publish-dynamic]");
    await expect(publishEntry).toBeVisible();
    await expect(publishEntry).toHaveAttribute(
      "href",
      "/u/dynamics_one/activity/dynamics"
    );
    await publishEntry.click();
    await expect(page).toHaveURL(/\/u\/dynamics_one\/activity\/dynamics$/);

    await expect(page.locator("[data-test-personal-dynamics]")).toBeVisible();
    await expect(
      page.locator("[data-test-personal-dynamics-publisher]")
    ).toBeVisible();
    await expect(
      page.locator("[data-test-personal-dynamics-publisher] input[type='file']")
    ).toHaveCount(0);

    const input = page.locator("[data-test-personal-dynamics-input]");
    const raw = `${crypto.randomUUID()} ${crypto.randomUUID()} I am planning a small English speaking practice this weekend.`;
    await input.fill(raw);
    await expect(
      page.locator("[data-test-personal-dynamics-count]")
    ).toHaveText(`${Array.from(raw).length}/500`);
    await page.locator("[data-test-personal-dynamics-publish]").click();

    const card = page.locator("[data-test-personal-dynamic]").first();
    await expect(card).toContainText("English speaking practice");
    dynamicUrl = await card
      .locator("[data-test-personal-dynamic-open]")
      .getAttribute("href");
    expect(dynamicUrl).toMatch(/^\/t\/.+\/\d+$/);
  });

  test("another member discovers the update, opens it, and replies natively", async ({
    context,
    page,
  }) => {
    await authenticate(context, "dynamics_two");
    await page.goto("/u/dynamics_one/activity/dynamics");

    await expect(
      page.locator("[data-test-personal-dynamics-publisher]")
    ).toHaveCount(0);
    await expect(
      page.locator("[data-test-personal-dynamic]").first()
    ).toContainText("English speaking practice");
    await page.locator("[data-test-personal-dynamic-open]").first().click();
    await expect(page).toHaveURL(dynamicUrl);

    await page.locator("#topic-footer-buttons .create").click();
    await expect(
      page.locator("[data-test-dynamic-reply-media-guard]")
    ).toBeVisible();
    await expect(
      page.locator("#reply-control .d-editor-button-bar .upload")
    ).toBeHidden();
    await page
      .locator(".d-editor-input")
      .fill(
        `${crypto.randomUUID()} I would like to join and compare practice notes.`
      );
    await page.locator(".save-or-cancel .create").click();
    await expect(page.locator(".topic-post")).toHaveCount(2);
    await expect(page.locator(".topic-post").last()).toContainText(
      "compare practice notes"
    );

    await context.clearCookies();
    await authenticate(context, "dynamics_one");
    const topicId = Number(dynamicUrl.split("/").at(-1));
    await expect
      .poll(async () => {
        const response = await page.request.get("/notifications.json");
        if (!response.ok()) {
          return false;
        }

        const notifications = await response.json();
        return notifications.notifications.some(
          (notification) => notification.topic_id === topicId
        );
      })
      .toBeTruthy();
  });

  test("homepage dynamics stay zero-request until the fourth group is selected", async ({
    context,
    page,
  }) => {
    await authenticate(context, "dynamics_two");
    let recentRequests = 0;
    page.on("request", (request) => {
      if (request.url().includes("/dynamics/recent.json")) {
        recentRequests += 1;
      }
    });

    await page.goto("/latest");
    await expect(page.locator("[data-test-community-discovery]")).toBeVisible();
    expect(recentRequests).toBe(0);
    await page.locator("[data-test-community-toggle]").click();
    expect(recentRequests).toBe(0);
    await page.locator("[data-test-community-group='dynamics']").click();

    await expect(
      page.locator("[data-test-community-dynamic]").first()
    ).toContainText("English speaking practice");
    expect(recentRequests).toBe(1);
  });

  test("a recommended member keeps all existing actions beside the dynamic preview", async ({
    context,
    page,
  }) => {
    await authenticate(context, "dynamics_two");
    await page.goto("/latest");
    await page.locator("[data-test-community-toggle]").click();
    await page.locator("[data-test-community-group='people']").click();

    const member = page.locator("[data-test-community-person='dynamics_one']");
    await expect(
      member.locator("[data-test-community-person-dynamic]")
    ).toContainText("English speaking practice");
    await expect(
      member.locator("[data-test-community-person-profile-action]")
    ).toBeVisible();
    await expect(member.locator("[data-test-community-dismiss]")).toBeVisible();
  });

  test("anonymous and media bypasses are rejected and normal topic lists stay clean", async ({
    browser,
    context,
    page,
  }) => {
    const anonymous = await browser.newContext();
    const anonymousPage = await anonymous.newPage();
    const endpointResponse = await anonymousPage.request.get(
      "/where-is-my-friends/dynamics.json?username=dynamics_one"
    );
    expect(endpointResponse.status()).toBe(403);
    await anonymousPage.goto(dynamicUrl);
    await expect(
      anonymousPage.getByRole("heading", {
        name: /page doesn.t exist or is private/i,
      })
    ).toBeVisible();
    await anonymous.close();

    await authenticate(context, "dynamics_one");
    await page.goto("/u/dynamics_one/activity/dynamics");
    const mediaStatus = await page.evaluate(async () => {
      const response = await fetch("/where-is-my-friends/dynamics.json", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")
            .content,
        },
        body: new URLSearchParams({
          raw: "![unsafe image](upload://not-allowed.png)",
        }),
      });
      return response.status;
    });
    expect(mediaStatus).toBe(422);

    await page.goto("/u/dynamics_one/activity/topics");
    await expect(page.locator("#main-outlet")).not.toContainText(
      "English speaking practice"
    );
  });

  test("@mobile dynamics layouts avoid horizontal overflow at tablet and phone widths", async ({
    context,
    page,
  }) => {
    await authenticate(context, "dynamics_one");
    for (const viewport of [
      { width: 820, height: 900 },
      { width: 390, height: 844 },
    ]) {
      await page.setViewportSize(viewport);
      await page.goto("/u/dynamics_one/activity/dynamics");
      await expect(page.locator("[data-test-personal-dynamics]")).toBeVisible();
      const sizes = await page.evaluate(() => ({
        viewport: window.innerWidth,
        content: document.documentElement.scrollWidth,
      }));
      expect(sizes.content).toBeLessThanOrEqual(sizes.viewport);
    }
  });
});
