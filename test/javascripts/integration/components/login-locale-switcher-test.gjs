import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import LoginLocaleSwitcher, {
  AVAILABLE_LOCALES,
} from "discourse/plugins/where-is-my-friends/discourse/components/login-locale-switcher";
import AboveSiteHeaderSwitcher from "discourse/plugins/where-is-my-friends/discourse/connectors/above-site-header/login-locale-switcher";

module("Integration | Component | login locale switcher", function (hooks) {
  setupRenderingTest(hooks);

  test("renders all 9 supported locales in select dropdown", async function (assert) {
    await render(<template><LoginLocaleSwitcher /></template>);

    assert.dom("[data-test-login-locale-switcher]").exists();
    assert.dom("[data-test-login-locale-select]").exists();

    const options = this.element.querySelectorAll(
      "[data-test-login-locale-select] option"
    );
    assert.strictEqual(
      options.length,
      AVAILABLE_LOCALES.length,
      "renders all supported languages"
    );

    const values = Array.from(options).map((opt) => opt.value);
    assert.true(values.includes("zh_CN"), "includes zh_CN");
    assert.true(values.includes("en"), "includes en");
    assert.true(values.includes("ja"), "includes ja");
  });

  test("above-site-header connector shouldRender only renders for anonymous users", function (assert) {
    const anonContext = {
      currentUser: null,
      siteSettings: { where_is_my_friends_enabled: true },
    };
    const loggedInContext = {
      currentUser: { id: 1, username: "user" },
      siteSettings: { where_is_my_friends_enabled: true },
    };
    const disabledContext = {
      currentUser: null,
      siteSettings: { where_is_my_friends_enabled: false },
    };

    assert.true(
      AboveSiteHeaderSwitcher.shouldRender({}, anonContext),
      "connector renders for anonymous visitor"
    );
    assert.false(
      AboveSiteHeaderSwitcher.shouldRender({}, loggedInContext),
      "connector does not render for logged in user"
    );
    assert.false(
      AboveSiteHeaderSwitcher.shouldRender({}, disabledContext),
      "connector does not render when plugin disabled"
    );
  });
});
