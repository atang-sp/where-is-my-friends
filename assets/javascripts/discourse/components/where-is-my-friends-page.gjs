import Component from "@glimmer/component";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import LocationDiscoveryWorkflow from "../lib/location-discovery-workflow";
import WhereIsMyFriendsResultsPanel from "./where-is-my-friends-results-panel";
import WhereIsMyFriendsSetupPanel from "./where-is-my-friends-setup-panel";

export default class WhereIsMyFriendsPage extends Component {
  @service currentUser;
  @service modal;
  @service router;
  @service siteSettings;

  constructor() {
    super(...arguments);
    this.workflow = new LocationDiscoveryWorkflow({
      model: this.args.model,
      currentUser: this.currentUser,
      modal: this.modal,
      router: this.router,
      siteSettings: this.siteSettings,
    });
  }

  <template>
    <main
      class="where-is-my-friends"
      data-state={{this.workflow.view.discoveryState}}
      {{didInsert this.workflow.intents.initialize}}
    >
      <header class="where-is-my-friends__header">
        <p class="where-is-my-friends__eyebrow">{{i18n
            "where_is_my_friends.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.title"}}</h1>
        <p>{{i18n "where_is_my_friends.description"}}</p>
      </header>

      {{#if this.workflow.view.error}}
        <div
          class="alert alert-error"
          data-test-error
        >{{this.workflow.view.error}}</div>
      {{/if}}

      {{#if this.workflow.view.setup}}
        <WhereIsMyFriendsSetupPanel
          @state={{this.workflow.view.setup}}
          @on={{this.workflow.intents.setup}}
        />
      {{else}}
        <WhereIsMyFriendsResultsPanel
          @state={{this.workflow.view.results}}
          @on={{this.workflow.intents.results}}
        />
      {{/if}}
    </main>
  </template>
}
