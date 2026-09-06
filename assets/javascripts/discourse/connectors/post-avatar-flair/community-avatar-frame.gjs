import CommunityAvatarFrame from "../../components/community-avatar-frame";

export default <template>
  {{yield}}
  {{#if @outletArgs.post.community_level}}
    <CommunityAvatarFrame
      @post={{@outletArgs.post}}
      @user={{@outletArgs.user}}
    />
  {{else if @outletArgs.user.community_level}}
    <CommunityAvatarFrame @user={{@outletArgs.user}} />
  {{/if}}
</template>
