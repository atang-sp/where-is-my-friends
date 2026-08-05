import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class AdminPluginsShowWhereIsMyFriendsAiProvidersRoute extends DiscourseRoute {
  model() {
    return ajax("/where-is-my-friends/admin/ai-provider-profiles.json");
  }

  titleToken() {
    return i18n("where_is_my_friends.admin.ai_providers.title");
  }
}
