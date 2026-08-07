import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class InterestOnboardingEditor extends Component {
  @action
  updateSearch(event) {
    this.args.on.changeDraft({ search: event.target.value });
  }

  @action
  selectPurpose(purpose) {
    this.args.on.changeDraft({ purpose });
  }

  @action
  updateRecommendable(event) {
    this.args.on.changeDraft({ recommendable: event.target.checked });
  }

  @action
  updatePublicInterests(event) {
    this.args.on.changeDraft({ showPublicly: event.target.checked });
  }

  <template>
    <section
      class="interest-onboarding__form"
      data-test-interest-onboarding-form
    >
      {{#if @state.catalogue.available.length}}
        <fieldset>
          <legend>{{i18n
              "where_is_my_friends.interests.choose_interests"
            }}</legend>
          <p>{{i18n "where_is_my_friends.interests.choose_interests_help"}}</p>
          <label class="interest-onboarding__search">
            <span>{{i18n "where_is_my_friends.interests.search_label"}}</span>
            <input
              type="search"
              value={{@state.catalogue.search}}
              placeholder={{i18n
                "where_is_my_friends.interests.search_placeholder"
              }}
              data-test-interest-search
              {{on "input" this.updateSearch}}
            />
          </label>

          {{#if @state.catalogue.groups.length}}
            <div
              class="interest-onboarding__interest-groups"
              data-test-interest-options
            >
              {{#each @state.catalogue.groups as |group|}}
                <section
                  class="interest-onboarding__interest-group
                    {{if
                      group.isSingle
                      'interest-onboarding__interest-group--single'
                    }}"
                  data-test-interest-group={{group.key}}
                  data-selection-mode={{group.selection_mode}}
                >
                  <div class="interest-onboarding__group-header">
                    <h3>{{group.name}}
                      {{#if group.isSingle}}
                        <span class="interest-onboarding__group-badge">{{i18n
                            "where_is_my_friends.interests.single_select"
                          }}</span>
                      {{/if}}
                    </h3>
                    {{#if group.description}}
                      <p>{{group.description}}</p>
                    {{/if}}
                    {{#if group.maxPerGroup}}
                      {{#unless group.isSingle}}
                        <span
                          class="interest-onboarding__group-count
                            {{if
                              group.groupFull
                              'interest-onboarding__group-count--full'
                            }}"
                        >{{i18n
                            "where_is_my_friends.interests.group_count"
                            count=group.selectedCount
                            maximum=group.maxPerGroup
                          }}</span>
                      {{/unless}}
                    {{/if}}
                  </div>
                  <div
                    class="interest-onboarding__chips"
                    role={{if group.isSingle "radiogroup" "group"}}
                  >
                    {{#each group.interests as |interest|}}
                      <DButton
                        @action={{fn @on.toggleInterest interest.id}}
                        @translatedLabel={{interest.name}}
                        @icon={{if interest.selected "check" "plus"}}
                        @disabled={{@state.status.loading}}
                        class={{if
                          interest.selected
                          "btn-primary"
                          "btn-default"
                        }}
                        aria-pressed={{if interest.selected "true" "false"}}
                        data-test-interest={{interest.name}}
                      />
                    {{/each}}
                  </div>
                </section>
              {{/each}}
            </div>
          {{else}}
            <p
              class="interest-onboarding__search-empty"
              data-test-interest-search-empty
            >{{i18n "where_is_my_friends.interests.search_empty"}}</p>
          {{/if}}
          <p
            class="interest-onboarding__selection-count"
            data-test-interest-count
          >{{i18n
              "where_is_my_friends.interests.selection_count"
              count=@state.selection.ids.size
              maximum=@state.selection.maximum
            }}</p>
        </fieldset>

        <fieldset>
          <legend>{{i18n
              "where_is_my_friends.interests.choose_purpose"
            }}</legend>
          <div class="interest-onboarding__chips" data-test-purpose-options>
            {{#each @state.purpose.options as |option|}}
              <DButton
                @action={{fn this.selectPurpose option.id}}
                @translatedLabel={{option.label}}
                @disabled={{@state.status.loading}}
                class={{if option.selected "btn-primary" "btn-default"}}
                aria-pressed={{if option.selected "true" "false"}}
                data-test-purpose={{option.id}}
              />
            {{/each}}
          </div>
        </fieldset>

        <fieldset class="interest-onboarding__privacy">
          <legend>{{i18n
              "where_is_my_friends.interests.privacy_title"
            }}</legend>
          <label>
            <input
              type="checkbox"
              checked={{@state.privacy.recommendable}}
              data-test-recommendable
              {{on "change" this.updateRecommendable}}
            />
            <span>{{i18n "where_is_my_friends.interests.recommendable"}}</span>
          </label>
          <label>
            <input
              type="checkbox"
              checked={{@state.privacy.showPublicly}}
              data-test-public-interests
              {{on "change" this.updatePublicInterests}}
            />
            <span>{{i18n
                "where_is_my_friends.interests.public_interests"
              }}</span>
          </label>
          <p>{{i18n "where_is_my_friends.interests.private_by_default"}}</p>
        </fieldset>

        <div class="interest-onboarding__form-actions">
          <DButton
            @action={{fn @on.submit "save"}}
            @label="where_is_my_friends.interests.save"
            @icon="sparkles"
            @disabled={{not @state.selection.canSave}}
            class="btn-primary"
            data-test-save-interests
          />
          {{#if (eq @state.status.state "pending")}}
            <DButton
              @action={{fn @on.submit "skip"}}
              @label="where_is_my_friends.interests.skip"
              @disabled={{@state.status.loading}}
              class="btn-flat"
              data-test-skip-interests
            />
          {{/if}}
        </div>
      {{else}}
        <div class="alert alert-info" data-test-interest-catalogue-empty>
          {{i18n "where_is_my_friends.interests.catalogue_empty"}}
        </div>
        <DButton
          @action={{fn @on.submit "skip"}}
          @label="where_is_my_friends.interests.skip"
          @disabled={{@state.status.loading}}
          class="btn-flat"
          data-test-skip-interests
        />
      {{/if}}
    </section>
  </template>
}
