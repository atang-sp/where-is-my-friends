import CommunityAvatarFrame from "../../components/community-avatar-frame";

export default <template>
  {{#if @outletArgs.model.community_level}}
    <CommunityAvatarFrame @model={{@outletArgs.model}} />
  {{else if @outletArgs.user.community_level}}
    <CommunityAvatarFrame @user={{@outletArgs.user}} />
  {{/if}}
</template>
