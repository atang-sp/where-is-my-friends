import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import AiProviderProfiles from "discourse/plugins/where-is-my-friends/discourse/components/ai-provider-profiles";

module("Integration | Component | ai-provider-profiles", function (hooks) {
  setupRenderingTest(hooks);

  test("shows masked provider state and gates activation on verification", async function (assert) {
    const initialState = {
      credential_master_key_configured: true,
      licensed_import_enabled: false,
      profiles: [
        {
          id: 7,
          name: "Primary gateway",
          purpose: "generation",
          protocol: "responses",
          base_url: "https://gateway.example/v1",
          model: "supplier-model",
          api_key_configured: true,
          active: false,
          verified: false,
          last_test_status: null,
        },
      ],
    };

    await render(
      <template>
        <AiProviderProfiles @initialState={{initialState}} />
      </template>
    );

    assert.dom("[data-provider-id='7']").includesText("Primary gateway");
    assert.dom("[data-provider-id='7']").includesText("supplier-model");
    assert.dom("[data-provider-id='7']").includesText("Configured");
    assert.dom("[data-provider-id='7']").doesNotIncludeText("never-return-this");
    assert.dom("[data-provider-id='7'] .ai-provider-profiles__activate").isDisabled();
    assert.dom(".ai-provider-profiles__master-key").hasClass("is-ready");
  });
});
