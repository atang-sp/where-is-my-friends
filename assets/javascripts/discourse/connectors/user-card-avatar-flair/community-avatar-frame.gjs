import CommunityAvatarFrame from "../../components/community-avatar-frame";

export default <template>
  {{#if @outletArgs.user.community_level}}
    <CommunityAvatarFrame @user={{@outletArgs.user}} />
  {{else if @outletArgs.model.community_level}}
    <CommunityAvatarFrame @model={{@outletArgs.model}} />
  {{/if}}
</template>;
