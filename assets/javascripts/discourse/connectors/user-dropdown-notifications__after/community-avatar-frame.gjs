import Component from "@glimmer/component";
import { service } from "@ember/service";
import CommunityAvatarFrame from "../../components/community-avatar-frame";

export default class HeaderAvatarFrameConnector extends Component {
  @service currentUser;

  <template>
    {{#if this.currentUser.community_level}}
      <CommunityAvatarFrame @user={{this.currentUser}} />
    {{/if}}
  </template>
}
