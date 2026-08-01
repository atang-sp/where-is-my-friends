import DBreadcrumbsItem from "discourse/ui-kit/d-breadcrumbs-item";
import { i18n } from "discourse-i18n";
import AiProviderProfiles from "discourse/plugins/where-is-my-friends/discourse/components/ai-provider-profiles";

export default <template>
  <DBreadcrumbsItem
    @path="/admin/plugins/where-is-my-friends/ai-providers"
    @label={{i18n "where_is_my_friends.admin.ai_providers.title"}}
  />

  <AiProviderProfiles @initialState={{@controller.model}} />
</template>
