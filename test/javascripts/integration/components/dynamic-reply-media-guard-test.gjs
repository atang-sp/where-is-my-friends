import { getOwner } from "@ember/owner";
import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import DynamicReplyMediaGuard from "discourse/plugins/where-is-my-friends/discourse/connectors/composer-fields-below/dynamic-reply-media-guard";

module("Integration | Component | dynamic reply media guard", function (hooks) {
  setupRenderingTest(hooks);

  test("keeps upload guidance active for retained dynamics after rollback", async function (assert) {
    getOwner(this).lookup(
      "service:site-settings"
    ).where_is_my_friends_dynamics_enabled = false;
    this.outletArgs = {
      model: { where_is_my_friends_dynamic: true },
    };

    await render(
      <template>
        <div id="reply-control">
          <DynamicReplyMediaGuard @outletArgs={{this.outletArgs}} />
        </div>
      </template>
    );

    assert.dom("[data-test-dynamic-reply-media-guard]").exists();
    assert
      .dom("#reply-control")
      .hasClass("where-is-my-friends-dynamic-composer");
  });
});
