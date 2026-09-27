import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

export default class CommunityDiscoveryDynamics extends Component {
  <template>
    {{#if @dynamics.length}}
      <section class="community-discovery__section">
        <h3>{{i18n
            "where_is_my_friends.community_discovery.dynamics_title"
          }}</h3>
        <div class="community-discovery__grid">
          {{#each @dynamics as |dynamic|}}
            <article data-test-community-dynamic={{dynamic.id}}>
              <div class="community-discovery__person-heading">
                <h4>{{if
                    dynamic.author.name
                    dynamic.author.name
                    dynamic.author.username
                  }}</h4>
                <span>@{{dynamic.author.username}}</span>
              </div>
              <p>{{dynamic.excerpt}}</p>
              <div class="community-discovery__actions">
                <a
                  class="btn btn-primary"
                  href={{dynamic.url}}
                  data-test-community-dynamic-open
                  {{on "click" (fn @trackDynamicOpen "dynamic_opened" dynamic)}}
                >{{i18n "where_is_my_friends.dynamics.open_and_reply"}}</a>
              </div>
            </article>
          {{/each}}
        </div>
      </section>
    {{else}}
      <div
        class="community-discovery__empty"
        data-test-community-dynamics-empty
      >
        <span>{{i18n
            "where_is_my_friends.community_discovery.dynamics_empty"
          }}</span>
        <a class="btn btn-flat" href={{@ownDynamicsUrl}}>
          {{i18n "where_is_my_friends.community_discovery.share_dynamic"}}
        </a>
      </div>
    {{/if}}
  </template>
}
