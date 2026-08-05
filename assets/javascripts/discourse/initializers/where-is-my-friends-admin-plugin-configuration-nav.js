import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "where-is-my-friends";

export default {
  name: "where-is-my-friends-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "user-group");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "where_is_my_friends.admin.ai_providers.title",
          route: "adminPlugins.show.where-is-my-friends-ai-providers",
          description: "where_is_my_friends.admin.ai_providers.nav_description",
        },
      ]);
    });
  },
};
