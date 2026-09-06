import CommunityAvatarFrame from "../../components/community-avatar-frame";

export default <template>
  {{#if @outletArgs.post.community_level}}
    <CommunityAvatarFrame @post={{@outletArgs.post}} />
  {{/if}}
</template>;
