import CommunityAvatarFrame from "../../components/community-avatar-frame";

export default <template>
  {{yield}}
  {{#if @outletArgs.topic.lastPosterUser.community_level}}
    <CommunityAvatarFrame @user={{@outletArgs.topic.lastPosterUser}} />
  {{/if}}
</template>
