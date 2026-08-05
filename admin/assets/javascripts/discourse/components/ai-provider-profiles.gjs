import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq, not, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";

const API_ROOT = "/where-is-my-friends/admin/ai-provider-profiles";

export default class AiProviderProfiles extends Component {
  @service dialog;
  @service toasts;

  @tracked profiles;
  @tracked licensedImportEnabled;
  @tracked editingId = null;
  @tracked name = "";
  @tracked protocol = "responses";
  @tracked structuredOutputMode = "json_schema";
  @tracked baseUrl = "";
  @tracked model = "";
  @tracked apiKey = "";
  @tracked saving = false;
  @tracked busyProfileId = null;

  constructor() {
    super(...arguments);
    this.profiles = this.args.initialState.profiles;
    this.licensedImportEnabled = this.args.initialState.licensed_import_enabled;
  }

  get isChatCompletions() {
    return this.protocol === "chat_completions";
  }

  @action
  updateName(event) {
    this.name = event.target.value;
  }

  @action
  updateProtocol(event) {
    this.protocol = event.target.value;
  }

  @action
  updateStructuredOutputMode(event) {
    this.structuredOutputMode = event.target.value;
  }

  @action
  updateBaseUrl(event) {
    this.baseUrl = event.target.value;
  }

  @action
  updateModel(event) {
    this.model = event.target.value;
  }

  @action
  updateApiKey(event) {
    this.apiKey = event.target.value;
  }

  @action
  edit(profile) {
    this.editingId = profile.id;
    this.name = profile.name;
    this.protocol = profile.protocol;
    this.structuredOutputMode = profile.structured_output_mode;
    this.baseUrl = profile.base_url;
    this.model = profile.model;
    this.apiKey = "";
  }

  @action
  cancelEdit() {
    this.resetForm();
  }

  @action
  async save(event) {
    event.preventDefault();
    this.saving = true;
    const url = this.editingId
      ? `${API_ROOT}/${this.editingId}.json`
      : `${API_ROOT}.json`;

    try {
      await ajax(url, {
        type: this.editingId ? "PUT" : "POST",
        data: {
          profile: {
            name: this.name,
            protocol: this.protocol,
            structured_output_mode: this.structuredOutputMode,
            base_url: this.baseUrl,
            model: this.model,
            api_key: this.apiKey,
          },
        },
      });
      this.resetForm();
      await this.reload();
      this.toasts.success({
        data: { message: i18n("where_is_my_friends.admin.ai_providers.saved") },
        duration: "short",
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async testProvider(profile) {
    this.busyProfileId = profile.id;
    try {
      await ajax(`${API_ROOT}/${profile.id}/test.json`, { type: "POST" });
      await this.reload();
      this.toasts.success({
        data: {
          message: i18n("where_is_my_friends.admin.ai_providers.test_passed"),
        },
        duration: "short",
      });
    } catch (error) {
      await this.reload();
      popupAjaxError(error);
    } finally {
      this.busyProfileId = null;
    }
  }

  @action
  async activate(profile) {
    this.busyProfileId = profile.id;
    try {
      await ajax(`${API_ROOT}/${profile.id}/activate.json`, { type: "POST" });
      await this.reload();
      this.toasts.success({
        data: {
          message: i18n("where_is_my_friends.admin.ai_providers.activated"),
        },
        duration: "short",
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.busyProfileId = null;
    }
  }

  @action
  deleteProvider(profile) {
    this.dialog.deleteConfirm({
      message: i18n("where_is_my_friends.admin.ai_providers.delete_confirm", {
        name: profile.name,
      }),
      didConfirm: async () => {
        try {
          await ajax(`${API_ROOT}/${profile.id}.json`, { type: "DELETE" });
          if (this.editingId === profile.id) {
            this.resetForm();
          }
          await this.reload();
        } catch (error) {
          popupAjaxError(error);
        }
      },
    });
  }

  async reload() {
    const state = await ajax(`${API_ROOT}.json`);
    this.profiles = state.profiles;
    this.licensedImportEnabled = state.licensed_import_enabled;
  }

  resetForm() {
    this.editingId = null;
    this.name = "";
    this.protocol = "responses";
    this.structuredOutputMode = "json_schema";
    this.baseUrl = "";
    this.model = "";
    this.apiKey = "";
  }

  <template>
    <section class="admin-detail ai-provider-profiles">
      <DPageSubheader
        @titleLabel={{i18n "where_is_my_friends.admin.ai_providers.title"}}
        @descriptionLabel={{i18n
          "where_is_my_friends.admin.ai_providers.description"
        }}
      />

      {{#if this.licensedImportEnabled}}
        <p class="ai-provider-profiles__running-warning">
          {{i18n "where_is_my_friends.admin.ai_providers.import_running"}}
        </p>
      {{/if}}

      <div class="ai-provider-profiles__list">
        {{#if this.profiles.length}}
          {{#each this.profiles as |profile|}}
            <article
              class="ai-provider-profiles__card"
              data-provider-id={{profile.id}}
            >
              <div>
                <h3>{{profile.name}}</h3>
                <p>
                  {{i18n "where_is_my_friends.admin.ai_providers.generation"}}
                  ·
                  {{#if (eq profile.protocol "responses")}}
                    {{i18n
                      "where_is_my_friends.admin.ai_providers.protocol_responses"
                    }}
                  {{else}}
                    {{i18n
                      "where_is_my_friends.admin.ai_providers.protocol_chat_completions"
                    }}
                  {{/if}}
                  ·
                  {{profile.model}}
                </p>
                <p>{{profile.base_url}}</p>
                <p>
                  {{#if profile.api_key_configured}}
                    {{i18n
                      "where_is_my_friends.admin.ai_providers.key_configured"
                    }}
                  {{else}}
                    {{i18n
                      "where_is_my_friends.admin.ai_providers.key_missing"
                    }}
                  {{/if}}
                  ·
                  {{#if profile.active}}
                    {{i18n "where_is_my_friends.admin.ai_providers.active"}}
                  {{else if profile.verified}}
                    {{i18n "where_is_my_friends.admin.ai_providers.verified"}}
                  {{else}}
                    {{i18n
                      "where_is_my_friends.admin.ai_providers.not_verified"
                    }}
                  {{/if}}
                </p>
              </div>
              <div class="ai-provider-profiles__actions">
                <DButton
                  @action={{fn this.edit profile}}
                  @label="where_is_my_friends.admin.ai_providers.edit"
                  @icon="pencil"
                />
                <DButton
                  @action={{fn this.testProvider profile}}
                  @label="where_is_my_friends.admin.ai_providers.test"
                  @icon="plug"
                  @isLoading={{eq this.busyProfileId profile.id}}
                />
                <DButton
                  class="ai-provider-profiles__activate"
                  @action={{fn this.activate profile}}
                  @label="where_is_my_friends.admin.ai_providers.activate"
                  @icon="check"
                  @disabled={{or (not profile.verified) profile.active}}
                  @isLoading={{eq this.busyProfileId profile.id}}
                />
                <DButton
                  @action={{fn this.deleteProvider profile}}
                  @label="where_is_my_friends.admin.ai_providers.delete"
                  @icon="trash-can"
                  class="btn-danger"
                />
              </div>
            </article>
          {{/each}}
        {{else}}
          <p class="ai-provider-profiles__empty">
            {{i18n "where_is_my_friends.admin.ai_providers.empty"}}
          </p>
        {{/if}}
      </div>

      <form class="ai-provider-profiles__form" {{on "submit" this.save}}>
        <h3>
          {{if
            this.editingId
            (i18n "where_is_my_friends.admin.ai_providers.edit_title")
            (i18n "where_is_my_friends.admin.ai_providers.add_title")
          }}
        </h3>

        <label>
          {{i18n "where_is_my_friends.admin.ai_providers.name"}}
          <input value={{this.name}} {{on "input" this.updateName}} required />
        </label>
        <label>
          {{i18n "where_is_my_friends.admin.ai_providers.protocol"}}
          <select value={{this.protocol}} {{on "change" this.updateProtocol}}>
            <option value="responses">
              {{i18n
                "where_is_my_friends.admin.ai_providers.protocol_responses"
              }}
            </option>
            <option value="chat_completions">
              {{i18n
                "where_is_my_friends.admin.ai_providers.protocol_chat_completions"
              }}
            </option>
          </select>
        </label>
        {{#if this.isChatCompletions}}
          <label>
            {{i18n
              "where_is_my_friends.admin.ai_providers.structured_output_mode"
            }}
            <select
              value={{this.structuredOutputMode}}
              {{on "change" this.updateStructuredOutputMode}}
            >
              <option value="json_schema">
                {{i18n
                  "where_is_my_friends.admin.ai_providers.mode_json_schema"
                }}
              </option>
              <option value="json_object">
                {{i18n
                  "where_is_my_friends.admin.ai_providers.mode_json_object"
                }}
              </option>
            </select>
          </label>
        {{/if}}
        <label>
          {{i18n "where_is_my_friends.admin.ai_providers.base_url"}}
          <input
            type="url"
            value={{this.baseUrl}}
            placeholder={{i18n
              "where_is_my_friends.admin.ai_providers.base_url_placeholder"
            }}
            {{on "input" this.updateBaseUrl}}
            required
          />
        </label>
        <label>
          {{i18n "where_is_my_friends.admin.ai_providers.model"}}
          <input
            value={{this.model}}
            {{on "input" this.updateModel}}
            required
          />
        </label>

        <label>
          {{i18n "where_is_my_friends.admin.ai_providers.api_key"}}
          <input
            type="password"
            value={{this.apiKey}}
            autocomplete="new-password"
            {{on "input" this.updateApiKey}}
            required={{not this.editingId}}
          />
          {{#if this.editingId}}
            <small>{{i18n
                "where_is_my_friends.admin.ai_providers.key_unchanged"
              }}</small>
          {{/if}}
        </label>

        <div class="ai-provider-profiles__form-actions">
          <DButton
            @type="submit"
            @label="where_is_my_friends.admin.ai_providers.save"
            @icon="floppy-disk"
            @isLoading={{this.saving}}
            class="btn-primary"
          />
          {{#if this.editingId}}
            <DButton
              @action={{this.cancelEdit}}
              @label="where_is_my_friends.admin.ai_providers.cancel"
            />
          {{/if}}
        </div>
      </form>
    </section>
  </template>
}
