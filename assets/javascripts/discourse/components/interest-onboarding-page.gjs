import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import InvitationInbox from "../lib/invitation-inbox";
import PreferenceRecommendationSession from "../lib/preference-recommendation-session";
import InterestOnboardingEditor from "./interest-onboarding-editor";
import InterestOnboardingInvitations from "./interest-onboarding-invitations";
import InterestOnboardingResults from "./interest-onboarding-results";

export default class InterestOnboardingPage extends Component {
  @service currentUser;
  @service siteSettings;

  constructor() {
    super(...arguments);
    this.practiceInvitationsEnabled =
      this.siteSettings.where_is_my_friends_practice_invitations_enabled;
    this.preferences = new PreferenceRecommendationSession({
      model: this.args.model,
      currentUser: this.currentUser,
      practiceInvitationsEnabled: this.practiceInvitationsEnabled,
    });
    this.invitations = new InvitationInbox({ inviteTo: this.args.inviteTo });
    this.resultsIntents = Object.freeze({
      ...this.preferences.intents.results,
      openInvitation: this.invitations.intents.openInvitation,
    });
  }

  @action
  async initialize() {
    this.preferences.intents.initialize();
    if (this.practiceInvitationsEnabled) {
      await this.invitations.intents.initialize();
    }
  }

  <template>
    <main
      class="interest-onboarding"
      data-state={{this.preferences.view.state}}
      {{didInsert this.initialize}}
    >
      <header class="interest-onboarding__header">
        <p class="interest-onboarding__eyebrow">{{i18n
            "where_is_my_friends.interests.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.interests.title"}}</h1>
        <p>{{i18n "where_is_my_friends.interests.description"}}</p>
      </header>

      {{#if this.preferences.view.error}}
        <div class="alert alert-error" data-test-interest-error>
          {{this.preferences.view.error}}
        </div>
      {{/if}}

      {{#if this.preferences.view.loading}}
        <div class="alert alert-info" role="status" data-test-interest-loading>
          {{i18n "where_is_my_friends.interests.loading"}}
        </div>
      {{/if}}

      {{#if this.invitations.view.error}}
        <div class="alert alert-error" data-test-practice-invitation-error>
          {{this.invitations.view.error}}
        </div>
      {{/if}}

      {{#if this.invitations.view.loading}}
        <div
          class="alert alert-info"
          role="status"
          data-test-practice-invitation-loading
        >
          {{i18n "where_is_my_friends.interests.loading"}}
        </div>
      {{/if}}

      {{#if this.invitations.view.success}}
        <div
          class="alert alert-success"
          role="status"
          data-test-practice-invitation-success
        >
          {{this.invitations.view.success}}
        </div>
      {{/if}}

      <InterestOnboardingInvitations
        @state={{this.invitations.view.state}}
        @on={{this.invitations.intents}}
      />

      {{#if this.preferences.view.editor}}
        <InterestOnboardingEditor
          @state={{this.preferences.view.editor}}
          @on={{this.preferences.intents.editor}}
        />
      {{else if (eq this.preferences.view.state "dismissed")}}
        <section
          class="interest-onboarding__dismissed"
          data-test-interest-dismissed
        >
          <h2>{{i18n "where_is_my_friends.interests.dismissed_title"}}</h2>
          <p>{{i18n "where_is_my_friends.interests.dismissed_description"}}</p>
          <DButton
            @action={{this.preferences.intents.edit}}
            @label="where_is_my_friends.interests.enable"
            @icon="sparkles"
            class="btn-primary"
            data-test-enable-interests
          />
        </section>
      {{else}}
        <InterestOnboardingResults
          @state={{this.preferences.view.results}}
          @on={{this.resultsIntents}}
        />
      {{/if}}
    </main>
  </template>
}
